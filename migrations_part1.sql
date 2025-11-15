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
