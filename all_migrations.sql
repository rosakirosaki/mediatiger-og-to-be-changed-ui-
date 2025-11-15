/*
  # Add Admin Access Tracking and Secure IDs
  
  1. New Functions
    - `generate_secure_identifier()`: Generates unique IDs for users
    - `handle_new_user()`: Adds secure ID to new users
    - `is_admin()`: Verifies admin status
    - `get_user_by_secure_id()`: Safely retrieves user data
  
  2. New Tables
    - `admin_access`: Tracks admin access to user data
  
  3. Security
    - Enable RLS on admin_access table
    - Add policies for admin access
    - Update existing users with roles and secure IDs
*/

-- Create a function to generate a unique identifier
CREATE OR REPLACE FUNCTION public.generate_secure_identifier()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  new_id text;
  is_unique boolean := false;
BEGIN
  WHILE NOT is_unique LOOP
    new_id := 
      encode(gen_random_bytes(16), 'hex') || 
      '_' || 
      regexp_replace(
        encode(gen_random_bytes(8), 'base64'), 
        '[^a-zA-Z0-9,._-]', 
        '', 
        'g'
      );
    
    new_id := substring(new_id, 1, 64);
    
    SELECT NOT EXISTS (
      SELECT 1 FROM auth.users WHERE raw_user_meta_data->>'secure_id' = new_id
    ) INTO is_unique;
  END LOOP;

  RETURN new_id;
END;
$$;

-- Create admin_access table if it doesn't exist
CREATE TABLE IF NOT EXISTS public.admin_access (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_id uuid NOT NULL REFERENCES auth.users(id),
  accessed_user_id uuid NOT NULL REFERENCES auth.users(id),
  accessed_at timestamptz NOT NULL DEFAULT now(),
  access_reason text
);

-- Enable RLS on admin_access table
ALTER TABLE public.admin_access ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist
DO $$ 
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE tablename = 'admin_access' 
    AND policyname = 'Admin users can view access logs'
  ) THEN
    DROP POLICY "Admin users can view access logs" ON admin_access;
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE tablename = 'admin_access' 
    AND policyname = 'Admin users can log access'
  ) THEN
    DROP POLICY "Admin users can log access" ON admin_access;
  END IF;
END $$;

-- Create policies
CREATE POLICY "Admin users can view access logs" 
  ON public.admin_access
  FOR SELECT 
  USING (auth.uid() IN (
    SELECT id FROM auth.users WHERE raw_user_meta_data->>'role' = 'admin'
  ));

CREATE POLICY "Admin users can log access" 
  ON public.admin_access
  FOR INSERT
  WITH CHECK (auth.uid() IN (
    SELECT id FROM auth.users WHERE raw_user_meta_data->>'role' = 'admin'
  ));

-- Drop existing function if it exists
DROP FUNCTION IF EXISTS public.handle_new_user() CASCADE;

-- Create function to add secure_id to new users
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  secure_id text;
BEGIN
  secure_id := public.generate_secure_identifier();
  
  NEW.raw_user_meta_data := 
    COALESCE(NEW.raw_user_meta_data, '{}'::jsonb) || 
    jsonb_build_object('secure_id', secure_id);
    
  RETURN NEW;
END;
$$;

-- Create trigger to add secure_id to new users
CREATE TRIGGER on_auth_user_created
  BEFORE INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

-- Function to verify if a user is an admin
CREATE OR REPLACE FUNCTION public.is_admin(user_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM auth.users 
    WHERE id = user_id AND raw_user_meta_data->>'role' = 'admin'
  );
END;
$$;

-- Function to safely get a user by secure_id (admin only)
CREATE OR REPLACE FUNCTION public.get_user_by_secure_id(
  secure_id text,
  admin_id uuid,
  reason text DEFAULT 'Admin lookup'
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  user_record auth.users%ROWTYPE;
  result json;
BEGIN
  IF NOT public.is_admin(admin_id) THEN
    RAISE EXCEPTION 'Unauthorized access: admin privileges required';
  END IF;

  SELECT * INTO user_record
  FROM auth.users
  WHERE raw_user_meta_data->>'secure_id' = secure_id;

  IF user_record IS NULL THEN
    RETURN json_build_object('error', 'User not found with provided secure ID');
  END IF;

  INSERT INTO public.admin_access (
    admin_id, 
    accessed_user_id, 
    access_reason
  ) VALUES (
    admin_id, 
    user_record.id, 
    reason
  );

  RETURN json_build_object(
    'id', user_record.id,
    'email', user_record.email,
    'created_at', user_record.created_at,
    'user_metadata', user_record.raw_user_meta_data - 'secure_id',
    'last_sign_in_at', user_record.last_sign_in_at,
    'confirmed_at', user_record.confirmed_at
  );
END;
$$;

-- Update existing users' metadata
DO $$
BEGIN
  -- Add 'user' role to users without a role
  UPDATE auth.users
  SET raw_user_meta_data = 
    CASE
      WHEN raw_user_meta_data IS NULL OR NOT (raw_user_meta_data ? 'role') 
      THEN COALESCE(raw_user_meta_data, '{}'::jsonb) || jsonb_build_object('role', 'user')
      ELSE raw_user_meta_data
    END
  WHERE raw_user_meta_data IS NULL OR NOT (raw_user_meta_data ? 'role');
  
  -- Add secure_id to users without one
  UPDATE auth.users
  SET raw_user_meta_data = 
    CASE
      WHEN raw_user_meta_data IS NULL OR NOT (raw_user_meta_data ? 'secure_id') 
      THEN COALESCE(raw_user_meta_data, '{}'::jsonb) || jsonb_build_object('secure_id', public.generate_secure_identifier())
      ELSE raw_user_meta_data
    END
  WHERE raw_user_meta_data IS NULL OR NOT (raw_user_meta_data ? 'secure_id');
END
$$;/*
  # Create User Requests Table

  1. New Tables
    - `user_requests`
      - `id` (uuid, primary key)
      - `user_id` (uuid, references auth.users)
      - `interests` (text[], stores selected interests)
      - `other_interest` (text, optional custom interest)
      - `name` (text, user's full name)
      - `email` (text, user's email)
      - `youtube_link` (text, optional channel URL)
      - `status` (text, request status)
      - `created_at` (timestamptz)
      - `updated_at` (timestamptz)

  2. Security
    - Enable RLS
    - Add policies for users to:
      - Create their own requests
      - View their own requests
      - Update their own requests
*/

-- Create user_requests table if it doesn't exist
CREATE TABLE IF NOT EXISTS user_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  interests text[] NOT NULL,
  other_interest text,
  name text NOT NULL,
  email text NOT NULL,
  youtube_link text,
  status text NOT NULL DEFAULT 'pending',
  created_at timestamptz DEFAULT now() NOT NULL,
  updated_at timestamptz DEFAULT now() NOT NULL
);

-- Enable row level security
ALTER TABLE user_requests ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist
DO $$ 
BEGIN
  -- Drop create policy if it exists
  IF EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE tablename = 'user_requests' 
    AND policyname = 'Users can create their own requests'
  ) THEN
    DROP POLICY "Users can create their own requests" ON user_requests;
  END IF;

  -- Drop view policy if it exists
  IF EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE tablename = 'user_requests' 
    AND policyname = 'Users can view their own requests'
  ) THEN
    DROP POLICY "Users can view their own requests" ON user_requests;
  END IF;

  -- Drop update policy if it exists
  IF EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE tablename = 'user_requests' 
    AND policyname = 'Users can update their own requests'
  ) THEN
    DROP POLICY "Users can update their own requests" ON user_requests;
  END IF;
END $$;

-- Create policies
CREATE POLICY "Users can create their own requests"
  ON user_requests
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can view their own requests"
  ON user_requests
  FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

CREATE POLICY "Users can update their own requests"
  ON user_requests
  FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id);

-- Drop existing function if it exists
DROP FUNCTION IF EXISTS update_modified_column() CASCADE;

-- Create function to automatically update updated_at field
CREATE OR REPLACE FUNCTION update_modified_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Drop existing trigger if it exists
DROP TRIGGER IF EXISTS update_user_requests_modified ON user_requests;

-- Create trigger to update the updated_at timestamp
CREATE TRIGGER update_user_requests_modified
  BEFORE UPDATE ON user_requests
  FOR EACH ROW
  EXECUTE FUNCTION update_modified_column();/*
  # Create Profiles Table

  1. New Tables
    - `profiles`
      - `id` (uuid, primary key, references auth.users)
      - `full_name` (text)
      - `updated_at` (timestamptz)

  2. Security
    - Enable RLS
    - Add policies for users to:
      - Read their own profile
      - Update their own profile
    
  3. Automation
    - Add trigger to create profile on user signup
*/

-- Create a table for public profiles if it doesn't exist
CREATE TABLE IF NOT EXISTS profiles (
  id uuid REFERENCES auth.users ON DELETE CASCADE PRIMARY KEY,
  full_name text,
  updated_at timestamptz DEFAULT now()
);

-- Enable Row Level Security if not already enabled
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist
DO $$ 
BEGIN
  -- Drop view policy if it exists
  IF EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE tablename = 'profiles' 
    AND policyname = 'Users can view own profile'
  ) THEN
    DROP POLICY "Users can view own profile" ON profiles;
  END IF;

  -- Drop update policy if it exists
  IF EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE tablename = 'profiles' 
    AND policyname = 'Users can update own profile'
  ) THEN
    DROP POLICY "Users can update own profile" ON profiles;
  END IF;
END $$;

-- Create policies
CREATE POLICY "Users can view own profile" 
  ON profiles 
  FOR SELECT 
  USING (auth.uid() = id);

CREATE POLICY "Users can update own profile" 
  ON profiles 
  FOR UPDATE 
  USING (auth.uid() = id);

-- Drop existing function if it exists
DROP FUNCTION IF EXISTS handle_new_user() CASCADE;

-- Function to handle new user profiles
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name)
  VALUES (new.id, new.raw_user_meta_data->>'full_name');
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Drop existing trigger if it exists
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

-- Create trigger to handle new user profiles
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();/*
  # Create Form Submissions Table

  1. New Tables
    - `form_submissions`
      - `id` (uuid, primary key)
      - `name` (text, not null)
      - `email` (text, not null)
      - `message` (text, not null)
      - `created_at` (timestamptz)

  2. Security
    - Enable RLS
    - Add policies for:
      - Admins to read all submissions
      - Anonymous users to submit forms
    
  3. Performance
    - Add index on email column for faster lookups
*/

-- Create form submissions table
CREATE TABLE IF NOT EXISTS form_submissions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  email text NOT NULL,
  message text NOT NULL,
  created_at timestamptz DEFAULT now()
);

-- Enable Row Level Security
ALTER TABLE form_submissions ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist
DO $$ 
BEGIN
  -- Drop admin read policy if it exists
  IF EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE tablename = 'form_submissions' 
    AND policyname = 'Admins can read all form submissions'
  ) THEN
    DROP POLICY "Admins can read all form submissions" ON form_submissions;
  END IF;

  -- Drop anonymous insert policy if it exists
  IF EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE tablename = 'form_submissions' 
    AND policyname = 'Anyone can submit contact forms'
  ) THEN
    DROP POLICY "Anyone can submit contact forms" ON form_submissions;
  END IF;
END $$;

-- Create policies
CREATE POLICY "Admins can read all form submissions"
  ON form_submissions
  FOR SELECT
  TO authenticated
  USING (auth.jwt() ->> 'role' = 'service_role' OR auth.jwt() ->> 'role' = 'supabase_admin');

CREATE POLICY "Anyone can submit contact forms"
  ON form_submissions
  FOR INSERT
  TO anon
  WITH CHECK (true);

-- Create index on email for faster lookups
CREATE INDEX IF NOT EXISTS idx_email ON form_submissions(email);/*
  # Add YouTube Links Array Column

  1. Changes
    - Add youtube_links array column to user_requests table
    - Migrate existing youtube_link data to new array column
    - Drop old youtube_link column
  
  2. Purpose
    - Support multiple YouTube channel URLs per user request
*/

-- Add new array column
ALTER TABLE user_requests 
ADD COLUMN youtube_links text[] DEFAULT '{}';

-- Migrate existing data
UPDATE user_requests 
SET youtube_links = ARRAY[youtube_link]
WHERE youtube_link IS NOT NULL AND youtube_link != '';

-- Drop old column
ALTER TABLE user_requests 
DROP COLUMN youtube_link;/*
  # Add Digital Rights Fields

  1. Changes
    - Add website column to user_requests table
    - Add youtube_channel column to user_requests table
  
  2. Purpose
    - Support digital rights management requests with website and channel info
*/

-- Add new columns for digital rights
ALTER TABLE user_requests 
ADD COLUMN website text,
ADD COLUMN youtube_channel text;/*
  # Add Admin Applications View and Functions
  
  1. New Views
    - `admin_applications_view`: Provides a consolidated view of user requests with related user data
  
  2. New Functions
    - `update_application_status`: Updates request status and logs admin actions
  
  3. Security
    - Views and functions restricted to admin users only
    - Proper schema ownership and permissions
*/

-- Create view for admin applications
CREATE VIEW admin_applications_view AS
SELECT 
  ur.id,
  ur.user_id,
  ur.interests,
  ur.other_interest,
  ur.name,
  ur.email,
  ur.youtube_channel,
  ur.website,
  ur.status,
  ur.created_at,
  ur.updated_at,
  u.raw_user_meta_data->>'verification_code' as verification_code,
  u.email as user_email,
  u.created_at as user_created_at
FROM user_requests ur
JOIN auth.users u ON ur.user_id = u.id;

-- Grant permissions to authenticated users
GRANT SELECT ON admin_applications_view TO authenticated;

-- Function to update application status
CREATE OR REPLACE FUNCTION update_application_status(
  application_id uuid,
  new_status text,
  admin_id uuid,
  reason text DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Verify admin privileges
  IF NOT (SELECT is_admin(admin_id)) THEN
    RAISE EXCEPTION 'Unauthorized: Admin privileges required';
  END IF;

  -- Update the status
  UPDATE user_requests
  SET 
    status = new_status,
    updated_at = now()
  WHERE id = application_id;

  -- Log the admin action
  INSERT INTO admin_access (
    admin_id,
    accessed_user_id,
    access_reason
  )
  SELECT 
    admin_id,
    user_id,
    COALESCE(reason, 'Application status updated to: ' || new_status)
  FROM user_requests
  WHERE id = application_id;

  RETURN true;
END;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION update_application_status TO authenticated;/*
  # Add YouTube Links Array Column

  1. Changes
    - Add youtube_links array column to user_requests table
  
  2. Purpose
    - Store multiple YouTube channel URLs per user request
    - Support channel management and music partner program features
*/

-- Add youtube_links array column if it doesn't exist
DO $$ 
BEGIN
  IF NOT EXISTS (
    SELECT 1 
    FROM information_schema.columns 
    WHERE table_schema = 'public' 
    AND table_name = 'user_requests' 
    AND column_name = 'youtube_links'
  ) THEN
    ALTER TABLE user_requests 
    ADD COLUMN youtube_links text[] DEFAULT '{}';
  END IF;
END $$;/*
  # Add YouTube Channel Link Uniqueness

  1. Changes
    - Add unique constraint on youtube_links array elements
    - Add function to check for duplicate YouTube links
    - Add trigger to validate YouTube links before insert/update
  
  2. Purpose
    - Prevent the same YouTube channel from being linked to multiple accounts
    - Provide clear error messages when duplicate channels are detected
*/

-- Function to check for duplicate YouTube links
CREATE OR REPLACE FUNCTION check_youtube_link_uniqueness()
RETURNS trigger AS $$
DECLARE
  existing_request RECORD;
  link TEXT;
BEGIN
  -- Skip check if no YouTube links
  IF NEW.youtube_links IS NULL OR array_length(NEW.youtube_links, 1) IS NULL THEN
    RETURN NEW;
  END IF;

  -- Check each YouTube link
  FOREACH link IN ARRAY NEW.youtube_links
  LOOP
    -- Skip empty links
    IF link IS NOT NULL AND link != '' THEN
      -- Check if link exists in another request
      SELECT user_id, id INTO existing_request
      FROM user_requests
      WHERE youtube_links @> ARRAY[link]
        AND user_id != NEW.user_id
        AND id != NEW.id;
      
      IF FOUND THEN
        RAISE EXCEPTION 'YouTube channel % is already registered with another account', link;
      END IF;
    END IF;
  END LOOP;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Drop existing trigger if it exists
DROP TRIGGER IF EXISTS youtube_link_uniqueness_check ON user_requests;

-- Create trigger for YouTube link uniqueness check
CREATE TRIGGER youtube_link_uniqueness_check
  BEFORE INSERT OR UPDATE ON user_requests
  FOR EACH ROW
  EXECUTE FUNCTION check_youtube_link_uniqueness();

-- Add comment explaining the trigger
COMMENT ON TRIGGER youtube_link_uniqueness_check ON user_requests IS 
  'Ensures YouTube channels cannot be linked to multiple accounts';/*
  # Add Application Status Check Function
  
  1. New Functions
    - `check_application_status`: Returns the status of a user's application
      - Parameters:
        - user_id (uuid): The ID of the user to check
      - Returns: text (the application status)
  
  2. Purpose
    - Allow checking if a user's application has been approved or rejected
    - Used to control access to dashboard until admin decision
*/

-- Function to check application status
CREATE OR REPLACE FUNCTION check_application_status(user_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  app_status text;
BEGIN
  SELECT status INTO app_status
  FROM user_requests
  WHERE user_id = $1
  ORDER BY created_at DESC
  LIMIT 1;

  RETURN COALESCE(app_status, 'none');
END;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION check_application_status TO authenticated;/*
  # Update Admin Applications View
  
  1. Changes
    - Drop existing admin_applications_view
    - Create updated view with youtube_links array
  
  2. Purpose
    - Include YouTube channel links in admin view
    - Ensure all application data is properly displayed
*/

-- Drop the existing view if it exists
DROP VIEW IF EXISTS admin_applications_view;

-- Create updated view with youtube_links
CREATE VIEW admin_applications_view AS
SELECT 
  ur.id,
  ur.user_id,
  ur.interests,
  ur.other_interest,
  ur.name,
  ur.email,
  ur.youtube_channel,
  ur.website,
  ur.youtube_links,
  ur.status,
  ur.created_at,
  ur.updated_at,
  u.raw_user_meta_data->>'verification_code' as verification_code,
  u.email as user_email,
  u.created_at as user_created_at
FROM user_requests ur
JOIN auth.users u ON ur.user_id = u.id;

-- Grant permissions to authenticated users
GRANT SELECT ON admin_applications_view TO authenticated;/*
  # Update Application Status Handling
  
  1. Changes
    - Add function to handle application status updates
    - Update user metadata on approval/rejection
    - Reset onboarding status on rejection
  
  2. Purpose
    - Manage user access based on application status
    - Force rejected users to restart onboarding
*/

-- Drop existing function if it exists
DROP FUNCTION IF EXISTS update_application_status;

-- Create updated function with metadata handling
CREATE OR REPLACE FUNCTION update_application_status(
  application_id uuid,
  new_status text,
  admin_id uuid,
  reason text DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
  v_metadata jsonb;
BEGIN
  -- Verify admin privileges
  IF NOT (SELECT is_admin(admin_id)) THEN
    RAISE EXCEPTION 'Unauthorized: Admin privileges required';
  END IF;

  -- Get user_id from application
  SELECT user_id INTO v_user_id
  FROM user_requests
  WHERE id = application_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Application not found';
  END IF;

  -- Get current user metadata
  SELECT raw_user_meta_data INTO v_metadata
  FROM auth.users
  WHERE id = v_user_id;

  -- Update user metadata based on status
  IF new_status = 'approved' THEN
    -- For approved applications, mark onboarding as complete
    v_metadata = v_metadata || jsonb_build_object(
      'onboarding_complete', true,
      'application_status', 'approved'
    );
  ELSIF new_status = 'rejected' THEN
    -- For rejected applications, reset onboarding status
    v_metadata = v_metadata || jsonb_build_object(
      'onboarding_complete', false,
      'application_status', 'rejected'
    );
  END IF;

  -- Update user metadata
  UPDATE auth.users
  SET raw_user_meta_data = v_metadata
  WHERE id = v_user_id;

  -- Update the application status
  UPDATE user_requests
  SET 
    status = new_status,
    updated_at = now()
  WHERE id = application_id;

  -- Log the admin action
  INSERT INTO admin_access (
    admin_id,
    accessed_user_id,
    access_reason
  ) VALUES (
    admin_id,
    v_user_id,
    COALESCE(reason, 'Application status updated to: ' || new_status)
  );

  RETURN true;
END;
$$;/*
  # Check and Add Rejection Reason Column
  
  1. Changes
    - Safely check for rejection_reason column
    - Add column only if it doesn't exist
  
  2. Purpose
    - Ensure rejection_reason column exists without errors
    - Handle cases where column may already exist
*/

DO $$ 
BEGIN
  -- Check if column exists before trying to add it
  IF NOT EXISTS (
    SELECT 1 
    FROM information_schema.columns 
    WHERE table_schema = 'public' 
    AND table_name = 'user_requests' 
    AND column_name = 'rejection_reason'
  ) THEN
    -- Add the column if it doesn't exist
    ALTER TABLE user_requests 
    ADD COLUMN rejection_reason text;
  END IF;
END $$;/*
  # Create Messages System

  1. New Tables
    - `messages`
      - `id` (uuid, primary key)
      - `sender_id` (uuid, references auth.users)
      - `receiver_id` (uuid, references auth.users)
      - `content` (text)
      - `image_url` (text, optional)
      - `created_at` (timestamptz)
      - `read_at` (timestamptz, optional)

  2. Security
    - Enable RLS
    - Add policies for:
      - Users can send messages
      - Users can read their own messages
      - Users can mark received messages as read
*/

-- Create messages table
CREATE TABLE IF NOT EXISTS messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sender_id uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  receiver_id uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  content text NOT NULL,
  image_url text,
  created_at timestamptz DEFAULT now() NOT NULL,
  read_at timestamptz,
  CONSTRAINT valid_message CHECK (
    content IS NOT NULL AND content != ''
  )
);

-- Enable RLS
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;

-- Create policies
CREATE POLICY "Users can send messages"
  ON messages
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = sender_id);

CREATE POLICY "Users can read their own messages"
  ON messages
  FOR SELECT
  TO authenticated
  USING (auth.uid() IN (sender_id, receiver_id));

-- Create function to mark message as read
CREATE OR REPLACE FUNCTION mark_message_read(message_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE messages
  SET read_at = now()
  WHERE id = message_id
  AND receiver_id = auth.uid()
  AND read_at IS NULL;
  
  RETURN FOUND;
END;
$$;

-- Create policy for updating read status
CREATE POLICY "Users can mark messages as read"
  ON messages
  FOR UPDATE
  TO authenticated
  USING (
    auth.uid() = receiver_id
  )
  WITH CHECK (
    -- Only allow updating read_at field
    read_at IS NOT NULL AND
    read_at > created_at
  );

-- Create indexes for faster message lookups
CREATE INDEX idx_messages_participants 
ON messages(sender_id, receiver_id);

CREATE INDEX idx_messages_created_at 
ON messages(created_at DESC);

-- Create bucket for message images if it doesn't exist
INSERT INTO storage.buckets (id, name)
VALUES ('message-images', 'message-images')
ON CONFLICT (id) DO NOTHING;

-- Set up storage policy for message images
CREATE POLICY "Users can upload message images"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'message-images' AND
  auth.uid()::text = (storage.foldername(name))[1]
);

CREATE POLICY "Users can view message images"
ON storage.objects
FOR SELECT
TO authenticated
USING (bucket_id = 'message-images');/*
  # Create Messages Table and Storage

  1. New Tables
    - `messages`
      - `id` (uuid, primary key)
      - `sender_id` (uuid, references auth.users)
      - `receiver_id` (uuid, references auth.users)
      - `content` (text)
      - `image_url` (text, optional)
      - `created_at` (timestamptz)
      - `read_at` (timestamptz, optional)

  2. Security
    - Enable RLS
    - Add policies for:
      - Sending messages
      - Reading own messages
      - Marking messages as read
    
  3. Storage
    - Create bucket for message images
    - Set up storage policies
*/

-- Create messages table if it doesn't exist
CREATE TABLE IF NOT EXISTS messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sender_id uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  receiver_id uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  content text NOT NULL,
  image_url text,
  created_at timestamptz DEFAULT now() NOT NULL,
  read_at timestamptz,
  CONSTRAINT valid_message CHECK (
    content IS NOT NULL AND content != ''
  )
);

-- Enable RLS if not already enabled
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist
DO $$ 
BEGIN
  -- Drop send policy if it exists
  IF EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE tablename = 'messages' 
    AND policyname = 'Users can send messages'
  ) THEN
    DROP POLICY "Users can send messages" ON messages;
  END IF;

  -- Drop read policy if it exists
  IF EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE tablename = 'messages' 
    AND policyname = 'Users can read their own messages'
  ) THEN
    DROP POLICY "Users can read their own messages" ON messages;
  END IF;

  -- Drop update policy if it exists
  IF EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE tablename = 'messages' 
    AND policyname = 'Users can mark messages as read'
  ) THEN
    DROP POLICY "Users can mark messages as read" ON messages;
  END IF;
END $$;

-- Create policies
CREATE POLICY "Users can send messages"
  ON messages
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = sender_id);

CREATE POLICY "Users can read their own messages"
  ON messages
  FOR SELECT
  TO authenticated
  USING (auth.uid() IN (sender_id, receiver_id));

-- Create function to mark message as read
CREATE OR REPLACE FUNCTION mark_message_read(message_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE messages
  SET read_at = now()
  WHERE id = message_id
  AND receiver_id = auth.uid()
  AND read_at IS NULL;
  
  RETURN FOUND;
END;
$$;

-- Create policy for updating read status
CREATE POLICY "Users can mark messages as read"
  ON messages
  FOR UPDATE
  TO authenticated
  USING (
    auth.uid() = receiver_id
  )
  WITH CHECK (
    -- Only allow updating read_at field
    read_at IS NOT NULL AND
    read_at > created_at
  );

-- Create indexes for faster message lookups
DROP INDEX IF EXISTS idx_messages_participants;
DROP INDEX IF EXISTS idx_messages_created_at;

CREATE INDEX idx_messages_participants 
ON messages(sender_id, receiver_id);

CREATE INDEX idx_messages_created_at 
ON messages(created_at DESC);

-- Create bucket for message images if it doesn't exist
INSERT INTO storage.buckets (id, name)
VALUES ('message-images', 'message-images')
ON CONFLICT (id) DO NOTHING;

-- Drop existing storage policies if they exist
DO $$ 
BEGIN
  -- Drop upload policy if it exists
  IF EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE tablename = 'objects' 
    AND schemaname = 'storage'
    AND policyname = 'Users can upload message images'
  ) THEN
    DROP POLICY "Users can upload message images" ON storage.objects;
  END IF;

  -- Drop view policy if it exists
  IF EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE tablename = 'objects' 
    AND schemaname = 'storage'
    AND policyname = 'Users can view message images'
  ) THEN
    DROP POLICY "Users can view message images" ON storage.objects;
  END IF;
END $$;

-- Set up storage policy for message images
CREATE POLICY "Users can upload message images"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'message-images' AND
  auth.uid()::text = (storage.foldername(name))[1]
);

CREATE POLICY "Users can view message images"
ON storage.objects
FOR SELECT
TO authenticated
USING (bucket_id = 'message-images');/*
  # Add Notifications Table and Functions
  
  1. New Tables
    - `notifications`
      - `id` (uuid, primary key)
      - `user_id` (uuid, references auth.users)
      - `title` (text)
      - `content` (text)
      - `type` (text)
      - `read` (boolean)
      - `created_at` (timestamptz)
  
  2. Security
    - Enable RLS
    - Add policies for users to:
      - View their own notifications
      - Mark notifications as read
*/

-- Create notifications table
CREATE TABLE IF NOT EXISTS notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  title text NOT NULL,
  content text NOT NULL,
  type text NOT NULL,
  read boolean DEFAULT false,
  created_at timestamptz DEFAULT now() NOT NULL
);

-- Enable RLS
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

-- Create policies
CREATE POLICY "Users can view their own notifications"
  ON notifications
  FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

CREATE POLICY "Users can mark their notifications as read"
  ON notifications
  FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (
    -- Only allow updating read status
    read = true AND
    xmin = xmin
  );

-- Create index for faster lookups
CREATE INDEX idx_notifications_user_id_created_at 
ON notifications(user_id, created_at DESC);

-- Function to mark notification as read
CREATE OR REPLACE FUNCTION mark_notification_read(notification_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE notifications
  SET read = true
  WHERE id = notification_id
  AND user_id = auth.uid();
  
  RETURN FOUND;
END;
$$;

-- Function to create notification
CREATE OR REPLACE FUNCTION create_notification(
  p_user_id uuid,
  p_title text,
  p_content text,
  p_type text DEFAULT 'info'
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_notification_id uuid;
BEGIN
  INSERT INTO notifications (
    user_id,
    title,
    content,
    type
  ) VALUES (
    p_user_id,
    p_title,
    p_content,
    p_type
  )
  RETURNING id INTO v_notification_id;
  
  RETURN v_notification_id;
END;
$$;/*
  # Add Username Handle Support
  
  1. Changes
    - Add username column to auth.users metadata
    - Add unique constraint on username
    - Add username validation function
    - Update existing functions to use username
    - Add trigger to validate username format
  
  2. Purpose
    - Allow users to have unique @ handles
    - Ensure usernames follow proper format
    - Make user identification more human-readable
*/

-- Function to validate username format
CREATE OR REPLACE FUNCTION validate_username(username text)
RETURNS boolean
LANGUAGE plpgsql
AS $$
BEGIN
  -- Username rules:
  -- 1. Must be 3-30 characters
  -- 2. Can only contain letters, numbers, and underscores
  -- 3. Must start with a letter
  -- 4. Cannot end with an underscore
  RETURN username ~ '^[a-zA-Z][a-zA-Z0-9_]{1,28}[a-zA-Z0-9]$';
END;
$$;

-- Function to ensure username uniqueness and format
CREATE OR REPLACE FUNCTION check_username()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  username text;
BEGIN
  -- Get username from metadata
  username := NEW.raw_user_meta_data->>'username';
  
  -- Validate username format
  IF username IS NOT NULL AND NOT validate_username(username) THEN
    RAISE EXCEPTION 'Invalid username format. Username must be 3-30 characters, start with a letter, and contain only letters, numbers, and underscores.';
  END IF;
  
  -- Check uniqueness
  IF username IS NOT NULL AND EXISTS (
    SELECT 1 FROM auth.users 
    WHERE raw_user_meta_data->>'username' = username 
    AND id != NEW.id
  ) THEN
    RAISE EXCEPTION 'Username already taken';
  END IF;
  
  RETURN NEW;
END;
$$;

-- Create trigger for username validation
DROP TRIGGER IF EXISTS check_username_trigger ON auth.users;
CREATE TRIGGER check_username_trigger
  BEFORE INSERT OR UPDATE ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION check_username();

-- Update notification functions to support usernames
CREATE OR REPLACE FUNCTION create_notification(
  p_username text,
  p_title text,
  p_content text,
  p_type text DEFAULT 'info'
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_id uuid;
  v_notification_id uuid;
BEGIN
  -- Get user ID from username
  SELECT id INTO v_user_id
  FROM auth.users
  WHERE raw_user_meta_data->>'username' = p_username;
  
  IF NOT FOUND THEN
    RAISE EXCEPTION 'User not found with username: %', p_username;
  END IF;

  INSERT INTO notifications (
    user_id,
    title,
    content,
    type
  ) VALUES (
    v_user_id,
    p_title,
    p_content,
    p_type
  )
  RETURNING id INTO v_notification_id;
  
  RETURN v_notification_id;
END;
$$;

-- Function to get user's username
CREATE OR REPLACE FUNCTION get_username(user_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  username text;
BEGIN
  SELECT raw_user_meta_data->>'username'
  INTO username
  FROM auth.users
  WHERE id = user_id;
  
  RETURN username;
END;
$$;/*
  # Update Notifications System for Usernames
  
  1. Changes
    - Update create_notification function to use usernames
    - Add username validation
    - Update notification creation logic
  
  2. Purpose
    - Support @ usernames instead of user IDs
    - Maintain backward compatibility
    - Improve user experience
*/

-- Drop existing function if it exists
DROP FUNCTION IF EXISTS create_notification;

-- Create updated function that uses username
CREATE OR REPLACE FUNCTION create_notification(
  p_username text,
  p_title text,
  p_content text,
  p_type text DEFAULT 'info'
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_id uuid;
  v_notification_id uuid;
BEGIN
  -- Get user ID from username
  SELECT id INTO v_user_id
  FROM auth.users
  WHERE raw_user_meta_data->>'username' = p_username;
  
  IF NOT FOUND THEN
    RAISE EXCEPTION 'User not found with username: %', p_username;
  END IF;

  -- Create notification
  INSERT INTO notifications (
    user_id,
    title,
    content,
    type
  ) VALUES (
    v_user_id,
    p_title,
    p_content,
    p_type
  )
  RETURNING id INTO v_notification_id;
  
  RETURN v_notification_id;
END;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION create_notification TO authenticated;

-- Add comment for documentation
COMMENT ON FUNCTION create_notification IS 'Creates a notification for a user using their username';/*
  # Fix Username Handling
  
  1. Changes
    - Make username optional in user metadata
    - Update username validation to be more permissive
    - Fix user creation trigger
  
  2. Purpose
    - Allow users to sign up without immediate username requirement
    - Fix database errors during user creation
*/

-- Drop existing triggers and functions
DROP TRIGGER IF EXISTS check_username_trigger ON auth.users;
DROP FUNCTION IF EXISTS check_username();
DROP FUNCTION IF EXISTS validate_username();

-- Create updated username validation function
CREATE OR REPLACE FUNCTION validate_username(username text)
RETURNS boolean
LANGUAGE plpgsql
AS $$
BEGIN
  -- Username rules:
  -- 1. Must be 3-30 characters
  -- 2. Can only contain letters, numbers, and underscores
  -- 3. Must start with a letter
  -- 4. Cannot end with an underscore
  RETURN username IS NULL OR username ~ '^[a-zA-Z][a-zA-Z0-9_]{1,28}[a-zA-Z0-9]$';
END;
$$;

-- Create updated username check function
CREATE OR REPLACE FUNCTION check_username()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  username text;
BEGIN
  -- Get username from metadata if it exists
  username := NEW.raw_user_meta_data->>'username';
  
  -- Skip validation if no username is set
  IF username IS NULL THEN
    RETURN NEW;
  END IF;
  
  -- Validate username format
  IF NOT validate_username(username) THEN
    RAISE EXCEPTION 'Invalid username format. Username must be 3-30 characters, start with a letter, and contain only letters, numbers, and underscores.';
  END IF;
  
  -- Check uniqueness only if username is provided
  IF EXISTS (
    SELECT 1 FROM auth.users 
    WHERE raw_user_meta_data->>'username' = username 
    AND id != NEW.id
  ) THEN
    RAISE EXCEPTION 'Username already taken';
  END IF;
  
  RETURN NEW;
END;
$$;

-- Create new trigger for username validation
CREATE TRIGGER check_username_trigger
  BEFORE INSERT OR UPDATE ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION check_username();

-- Update notification function to handle null usernames
CREATE OR REPLACE FUNCTION create_notification(
  p_username text,
  p_title text,
  p_content text,
  p_type text DEFAULT 'info'
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_id uuid;
  v_notification_id uuid;
BEGIN
  -- Get user ID from username
  IF p_username IS NOT NULL THEN
    SELECT id INTO v_user_id
    FROM auth.users
    WHERE raw_user_meta_data->>'username' = p_username;
    
    IF NOT FOUND THEN
      RAISE EXCEPTION 'User not found with username: %', p_username;
    END IF;
  END IF;

  -- Create notification
  INSERT INTO notifications (
    user_id,
    title,
    content,
    type
  ) VALUES (
    COALESCE(v_user_id, auth.uid()),
    p_title,
    p_content,
    p_type
  )
  RETURNING id INTO v_notification_id;
  
  RETURN v_notification_id;
END;
$$;/*
  # Add Monthly Views Tracking
  
  1. New Tables
    - `channel_views`
      - `id` (uuid, primary key)
      - `channel_id` (text, YouTube channel ID)
      - `user_id` (uuid, references auth.users)
      - `month` (date, first day of month)
      - `views` (bigint, total views for month)
      - `created_at` (timestamptz)
      - `updated_at` (timestamptz)
  
  2. New Functions
    - `update_channel_views`: Updates monthly view count for a channel
    - `get_total_monthly_views`: Gets total views across all user's channels
  
  3. Security
    - Enable RLS
    - Add policies for users to view their own data
*/

-- Create channel_views table
CREATE TABLE IF NOT EXISTS channel_views (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  channel_id text NOT NULL,
  user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  month date NOT NULL,
  views bigint NOT NULL DEFAULT 0,
  created_at timestamptz DEFAULT now() NOT NULL,
  updated_at timestamptz DEFAULT now() NOT NULL,
  UNIQUE(channel_id, month)
);

-- Enable RLS
ALTER TABLE channel_views ENABLE ROW LEVEL SECURITY;

-- Create policies
CREATE POLICY "Users can view their own channel stats"
  ON channel_views
  FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

CREATE POLICY "Users can update their own channel stats"
  ON channel_views
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

-- Function to update channel views
CREATE OR REPLACE FUNCTION update_channel_views(
  p_channel_id text,
  p_user_id uuid,
  p_month date,
  p_views bigint
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO channel_views (channel_id, user_id, month, views)
  VALUES (p_channel_id, p_user_id, p_month, p_views)
  ON CONFLICT (channel_id, month)
  DO UPDATE SET 
    views = p_views,
    updated_at = now();
END;
$$;

-- Function to get total monthly views for a user
CREATE OR REPLACE FUNCTION get_total_monthly_views(
  p_user_id uuid,
  p_month date DEFAULT date_trunc('month', current_date)::date
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  total_views bigint;
BEGIN
  SELECT COALESCE(SUM(views), 0)
  INTO total_views
  FROM channel_views
  WHERE user_id = p_user_id
  AND month = p_month;
  
  RETURN total_views;
END;
$$;

-- Create index for faster lookups
CREATE INDEX idx_channel_views_user_month 
ON channel_views(user_id, month);

-- Add trigger to update updated_at
CREATE OR REPLACE FUNCTION update_channel_views_updated_at()
RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_channel_views_updated_at
  BEFORE UPDATE ON channel_views
  FOR EACH ROW
  EXECUTE FUNCTION update_channel_views_updated_at();/*
  # Add Tipalti Integration
  
  1. New Columns
    - Add tipalti_id to auth.users metadata
    - Add payment_enabled flag to auth.users metadata
  
  2. New Functions
    - generate_tipalti_id(): Generates unique Tipalti-compatible IDs
    - assign_tipalti_id(): Assigns Tipalti ID to new users after onboarding
  
  3. Security
    - Ensure IDs follow Tipalti requirements
    - Add validation for ID format
*/

-- Function to generate a unique Tipalti-compatible ID
CREATE OR REPLACE FUNCTION generate_tipalti_id()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  new_id text;
  is_unique boolean := false;
BEGIN
  -- Generate ID until a unique one is found
  WHILE NOT is_unique LOOP
    -- Generate base using timestamp and random elements
    new_id := 
      -- Use timestamp for uniqueness
      to_char(current_timestamp, 'YYYYMMDD') || '_' ||
      -- Add random alphanumeric string
      encode(gen_random_bytes(8), 'hex') || '_' ||
      -- Add random suffix
      encode(gen_random_bytes(4), 'base64');
    
    -- Clean up the ID to match Tipalti requirements
    new_id := regexp_replace(new_id, '[^a-zA-Z0-9,._-]', '', 'g');
    
    -- Ensure max length of 64
    new_id := substring(new_id, 1, 64);
    
    -- Check uniqueness
    SELECT NOT EXISTS (
      SELECT 1 FROM auth.users 
      WHERE raw_user_meta_data->>'tipalti_id' = new_id
    ) INTO is_unique;
  END LOOP;

  RETURN new_id;
END;
$$;

-- Function to assign Tipalti ID after onboarding
CREATE OR REPLACE FUNCTION assign_tipalti_id()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  tipalti_id text;
BEGIN
  -- Only assign ID if onboarding is complete and no ID exists
  IF (NEW.raw_user_meta_data->>'onboarding_complete')::boolean = true 
     AND (NEW.raw_user_meta_data->>'tipalti_id') IS NULL THEN
    
    -- Generate new Tipalti ID
    tipalti_id := generate_tipalti_id();
    
    -- Update user metadata with Tipalti ID
    NEW.raw_user_meta_data := NEW.raw_user_meta_data || jsonb_build_object(
      'tipalti_id', tipalti_id,
      'payment_enabled', true
    );
  END IF;
  
  RETURN NEW;
END;
$$;

-- Create trigger to assign Tipalti ID after onboarding
DROP TRIGGER IF EXISTS assign_tipalti_id_trigger ON auth.users;
CREATE TRIGGER assign_tipalti_id_trigger
  BEFORE UPDATE ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION assign_tipalti_id();

-- Function to validate Tipalti ID format
CREATE OR REPLACE FUNCTION validate_tipalti_id(id text)
RETURNS boolean
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN id ~ '^[a-zA-Z0-9,._-]{1,64}$';
END;
$$;

-- Update existing users who have completed onboarding but don't have Tipalti IDs
DO $$
DECLARE
  user_record RECORD;
  new_tipalti_id text;
BEGIN
  FOR user_record IN
    SELECT id, raw_user_meta_data
    FROM auth.users
    WHERE 
      (raw_user_meta_data->>'onboarding_complete')::boolean = true
      AND (raw_user_meta_data->>'tipalti_id') IS NULL
  LOOP
    -- Generate new Tipalti ID
    new_tipalti_id := generate_tipalti_id();
    
    -- Update user metadata
    UPDATE auth.users
    SET raw_user_meta_data = raw_user_meta_data || jsonb_build_object(
      'tipalti_id', new_tipalti_id,
      'payment_enabled', true
    )
    WHERE id = user_record.id;
  END LOOP;
END;
$$;