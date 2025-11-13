import React, { useState, useEffect } from "react";
import { Link, useNavigate } from "react-router-dom";
import { useAuth } from "../contexts/AuthContext";
import { supabase } from "../lib/supabase";
import { createPortal } from "react-dom";
import { formatRelativeTime, formatNumber } from "../utils/dateUtils";
import {
  LogOut,
  Settings,
  User,
  Eye,
  MessageSquare,
  Bell,
  BarChart3,
  Play,
  Shield,
  Globe,
  Menu,
  X,
  UserCircle,
  Mail,
  Calendar,
  Clock,
  Youtube,
  ExternalLink,
  ChevronRight,
  TrendingUp,
  BarChart2,
  Activity,
  Target,
  LineChart,
  TrendingDown,
  Award,
  Users as UsersIcon,
  ThumbsUp,
  DollarSign,
  Music,
  Wallet,
} from "lucide-react";
import OnboardingPopup from "../components/OnboardingPopup";
import Swal from "sweetalert2";
import { Line } from "react-chartjs-2";
import {
  Chart as ChartJS,
  CategoryScale,
  LinearScale,
  PointElement,
  LineElement,
  Title,
  Tooltip,
  Legend,
  Filler,
} from "chart.js";
import ChannelManagement from "./features/ChannelManagement";

// Register ChartJS components
ChartJS.register(
  CategoryScale,
  LinearScale,
  PointElement,
  LineElement,
  Title,
  Tooltip,
  Legend,
  Filler
);

interface Channel {
  url: string;
  views: number;
  monthlyViews: number;
  subscribers: number;
  growth: number;
}

interface ActivityItem {
  id: string;
  type: "view" | "subscriber" | "revenue" | "milestone";
  title: string;
  description: string;
  timestamp: string;
  metadata?: {
    amount?: number;
    trend?: "up" | "down";
    percentage?: number;
  };
}

interface GoalProgress {
  id: string;
  title: string;
  current: number;
  target: number;
  unit: string;
  color: string;
}

export default function Dashboard() {
  const { user, signOut, showOnboarding, setShowOnboarding } = useAuth();
  const [isMobileMenuOpen, setIsMobileMenuOpen] = useState(false);
  const [isLoading, setIsLoading] = useState(true);
  const [showNotifications, setShowNotifications] = useState(false);
  const [showSettings, setShowSettings] = useState(false);
  const [hasNewNotification, setHasNewNotification] = useState(false);
  const [hasUnreadMessages, setHasUnreadMessages] = useState(false);
  const [monthlyViews, setMonthlyViews] = useState(0);
  const [linkedChannels, setLinkedChannels] = useState(0);
  const [notifications, setNotifications] = useState<any[]>([]);
  const [selectedChannel, setSelectedChannel] = useState<Channel | null>(null);
  const [channels, setChannels] = useState<Channel[]>([]);
  const [reason, setReason] = useState("");
  const [isRejected, setIsRejected] = useState(false);
  const [hasChanel, setHasChanel] = useState(false);
  const [activeSection, setActiveSection] = useState("overview");
  const navigate = useNavigate();
  const [uploadingImage, setUploadingImage] = useState(false);
  const [profileImage, setProfileImage] = useState<string | null>(
    user?.user_metadata?.avatar_url || null
  );
  const [recentActivity, setRecentActivity] = useState<ActivityItem[]>([]);
  const [goals, setGoals] = useState<GoalProgress[]>([]);
  const [realtimeViews, setRealtimeViews] = useState({
    current: 0,
    last24h: 0,
    last48h: 0,
  });
  const [performanceData, setPerformanceData] = useState({
    labels: [] as string[],
    views: [] as number[],
    engagement: [] as number[],
    revenue: [] as number[],
  });

  const handleImageUpload = async (
    event: React.ChangeEvent<HTMLInputElement>
  ) => {
    try {
      const file = event.target.files?.[0];
      if (!file || !user) return;

      setUploadingImage(true);

      // Upload image to Supabase Storage
      const fileExt = file.name.split(".").pop();
      const fileName = `${user.id}-${Math.random()}.${fileExt}`;
      const filePath = `/${user.id}/${fileName}`;

      const { error: uploadError, data } = await supabase.storage
        .from("profile-pictures")
        .upload(filePath, file);

      if (uploadError) throw uploadError;

      // Get public URL
      const {
        data: { publicUrl },
      } = supabase.storage.from("profile-pictures").getPublicUrl(filePath);

      // Update user metadata
      const { error: updateError } = await supabase.auth.updateUser({
        data: { avatar_url: publicUrl },
      });

      if (updateError) throw updateError;

      setProfileImage(publicUrl);
    } catch (error) {
      console.error("Error uploading image:", error);
    } finally {
      setUploadingImage(false);
    }
  };

  useEffect(() => {
    if (!user) return;

    // Generate sample activity data
    const sampleActivity: ActivityItem[] = [
      {
        id: "1",
        type: "view",
        title: "Viewership Spike",
        description:
          'Your channel "Gaming Adventures" saw a 25% increase in views',
        timestamp: new Date(Date.now() - 1000 * 60 * 30).toISOString(),
        metadata: { amount: 25, trend: "up" },
      },
      {
        id: "2",
        type: "subscriber",
        title: "New Subscriber Milestone",
        description: "You've reached 100K subscribers!",
        timestamp: new Date(Date.now() - 1000 * 60 * 60).toISOString(),
        metadata: { amount: 100000 },
      },
      {
        id: "3",
        type: "revenue",
        title: "Revenue Update",
        description: "Monthly revenue increased by 15%",
        timestamp: new Date(Date.now() - 1000 * 60 * 60 * 2).toISOString(),
        metadata: { amount: 15, trend: "up" },
      },
      {
        id: "4",
        type: "milestone",
        title: "Achievement Unlocked",
        description: "Your video reached 1M views",
        timestamp: new Date(Date.now() - 1000 * 60 * 60 * 4).toISOString(),
      },
    ];
    setRecentActivity(sampleActivity);

    // Set sample goals
    const sampleGoals: GoalProgress[] = [
      {
        id: "1",
        title: "Monthly Views",
        current: 850000,
        target: 1000000,
        unit: "views",
        color: "indigo",
      },
      {
        id: "2",
        title: "Subscriber Growth",
        current: 75000,
        target: 100000,
        unit: "subscribers",
        color: "purple",
      },
      {
        id: "3",
        title: "Revenue Target",
        current: 8500,
        target: 10000,
        unit: "USD",
        color: "green",
      },
    ];
    setGoals(sampleGoals);

    // Generate sample performance data
    const last30Days = Array.from({ length: 30 }, (_, i) => {
      const date = new Date();
      date.setDate(date.getDate() - (29 - i));
      return date.toLocaleDateString("en-US", {
        month: "short",
        day: "numeric",
      });
    });

    const generateTrendData = () =>
      Array.from(
        { length: 30 },
        () => Math.floor(Math.random() * 100000) + 50000
      );

    setPerformanceData({
      labels: last30Days,
      views: generateTrendData(),
      engagement: generateTrendData().map((n) => n * 0.1),
      revenue: generateTrendData().map((n) => n * 0.01),
    });

    // Set sample realtime views
    setRealtimeViews({
      current: Math.floor(Math.random() * 5000) + 1000,
      last24h: Math.floor(Math.random() * 100000) + 50000,
      last48h: Math.floor(Math.random() * 150000) + 75000,
    });

    const fetchStats = async () => {
      if (!hasChanel) return;
      try {
        // Get current month's views
        const { data: viewsData, error: viewsError } = await supabase.rpc(
          "get_total_monthly_views",
          {
            p_user_id: user.id,
            p_month: new Date().toISOString().slice(0, 10),
          }
        );

        if (viewsError) throw viewsError;
        setMonthlyViews(viewsData || 0);

        // Get linked channels count
        const { data: requestData, error: requestError } = await supabase
          .from("user_requests")
          .select("youtube_links")
          .eq("user_id", user.id)
          .single();

        if (requestError) throw requestError;
        setLinkedChannels(requestData?.youtube_links?.length || 0);
      } catch (error) {
        console.error("Error fetching stats:", error);
      }
    };

    fetchStats();

    // Set up interval to check stats every hour
    const interval = setInterval(fetchStats, 3600000);
    return () => clearInterval(interval);
  }, [user]);

  // Effect to fetch and subscribe to notifications
  useEffect(() => {
    if (!user) return;

    const fetchNotifications = async () => {
      const { data, error } = await supabase
        .from("notifications")
        .select("*")
        .eq("user_id", user.id)
        .order("created_at", { ascending: false });

      if (error) {
        console.error("Error fetching notifications:", error);
        return;
      }

      setNotifications(
        data.map((notification) => ({
          id: notification.id,
          title: notification.title,
          content: notification.content,
          time: formatRelativeTime(notification.created_at),
          read: notification.read,
        }))
      );
    };

    fetchNotifications();

    // Subscribe to new notifications
    const subscription = supabase
      .channel("notifications")
      .on(
        "postgres_changes",
        {
          event: "*",
          schema: "public",
          table: "notifications",
          filter: `user_id=eq.${user.id}`,
        },
        async (payload) => {
          if (payload.eventType === "INSERT") {
            const newNotification = {
              id: payload.new.id,
              title: payload.new.title,
              content: payload.new.content,
              time: formatRelativeTime(payload.new.created_at),
              read: payload.new.read,
            };

            setNotifications((prev) => [newNotification, ...prev]);
            setHasNewNotification(true);

            // Play notification sound
            const audio = new Audio("/notification.mp3");
            audio.play().catch(() => {}); // Ignore errors if sound can't play
          }
        }
      )
      .subscribe();

    return () => {
      subscription.unsubscribe();
    };
  }, [user]);

  // Effect to check for unread messages
  useEffect(() => {
    if (!user) return;

    const checkUnreadMessages = async () => {
      const { data: messages, error } = await supabase
        .from("messages")
        .select("*")
        .eq("receiver_id", user.id)
        .is("read_at", null);

      if (error) {
        console.error("Error checking unread messages:", error);
        return;
      }

      setHasUnreadMessages(messages && messages.length > 0);
    };

    checkUnreadMessages();

    // Subscribe to new messages
    const subscription = supabase
      .channel("messages")
      .on(
        "postgres_changes",
        {
          event: "*",
          schema: "public",
          table: "messages",
          filter: `receiver_id=eq.${user.id}`,
        },
        () => {
          checkUnreadMessages();
        }
      )
      .subscribe();

    return () => {
      subscription.unsubscribe();
    };
  }, [user]);

  // Effect to handle notification animation
  useEffect(() => {
    if (notifications.some((n) => !n.read)) {
      setHasNewNotification(true);
      // Reset the animation after it plays
      const timer = setTimeout(() => {
        setHasNewNotification(false);
      }, 2000);
      return () => clearTimeout(timer);
    }
  }, [notifications]);

  const handleSignOut = async () => {
    try {
      await signOut();
    } catch (error) {
      console.error("Error signing out:", error);
    }
  };

  const clearNotifications = () => {
    // Update notifications as read in database
    if (!user) return;

    const updateNotifications = async () => {
      const { error } = await supabase
        .from("notifications")
        .update({ read: true })
        .eq("user_id", user.id);

      if (error) {
        console.error("Error clearing notifications:", error);
        return;
      }

      setNotifications([]);
      setHasNewNotification(false);
    };

    updateNotifications();
  };

  const markAllAsRead = () => {
    // Mark all notifications as read in database
    if (!user) return;

    const updateNotifications = async () => {
      const { error } = await supabase
        .from("notifications")
        .update({ read: true })
        .eq("user_id", user.id);

      if (error) {
        console.error("Error marking notifications as read:", error);
        return;
      }

      setNotifications((prev) => prev.map((n) => ({ ...n, read: true })));
      setHasNewNotification(false);
    };

    updateNotifications();
  };

  // Close dropdowns when clicking outside
  useEffect(() => {
    const handleClickOutside = (event: MouseEvent) => {
      const target = event.target as HTMLElement;
      if (
        !target.closest(".notifications-dropdown") &&
        !target.closest(".notifications-button")
      ) {
        setShowNotifications(false);
      }
      if (
        !target.closest(".settings-dropdown") &&
        !target.closest(".settings-button")
      ) {
        setShowSettings(false);
      }
    };

    document.addEventListener("mousedown", handleClickOutside);
    return () => document.removeEventListener("mousedown", handleClickOutside);
  }, []);

  useEffect(() => {
    const fecthUserRequest = async (userId: string) => {
      const { data: requestData, error: requestError } = await supabase
        .from("user_requests")
        .select("status,rejection_reason")
        .eq("user_id", userId);

      if (requestError) {
        console.error("Error fetching user requests:", requestError);
        throw requestError;
      }

      return requestData;
    };

    if (user?.user_metadata?.role === "admin") {
      navigate("/purple");
      setIsLoading(false);
      return;
    } else if (user) {
      fecthUserRequest(user?.id)
        .then((res) => {
          console.log(res);
          if (res.length == 0) {
            setShowOnboarding(true);
            setIsLoading(false);
            return;
          }
          if (res[0].status === "pending") {
            const popup = document.createElement("div");
            popup.className =
              "fixed inset-0 z-[60] flex items-center justify-center p-4 bg-slate-900";
            popup.innerHTML = `
        <div class="bg-slate-800 rounded-xl p-12 max-w-xl w-full text-center shadow-2xl border-2 border-indigo-500/20">
          <div class="w-20 h-20 mx-auto mb-8 rounded-full bg-indigo-600/20 flex items-center justify-center">
            <svg class="w-10 h-10 text-indigo-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
            </svg>
          </div>
          <h3 class="text-3xl font-bold text-white mb-6">Application Submitted</h3>
          <div class="mb-8">
            <div class="inline-flex items-center px-4 py-2 rounded-full text-base font-medium bg-gradient-to-r from-indigo-600 via-purple-600 to-indigo-600 text-white relative overflow-hidden shadow-lg" style="background-size: 200% 100%; animation: gradient-wave 3s ease infinite;">
              Pending
            </div>
          </div>
          <p class="text-slate-300 text-lg mb-4">Your application is under review.</p>
          <p class="text-slate-400">You will be automatically redirected to your dashboard once your application is approved.</p>
        </div>
      `;
            document.body.appendChild(popup);
          }
          if (res[0].status == "approved") {
            setHasChanel(true);
          }
          if (res[0].status == "rejected") {
            setReason(res[0]?.rejection_reason);
            setIsRejected(true);
            setIsLoading(false);
          }
          setIsLoading(false);
        })
        .catch((err) => {
          console.log(err);
        });
    }
  }, [user, setShowOnboarding, navigate]);

  const navigationItems = [
    {
      name: "Overview",
      section: "overview",
      icon: <Eye className="h-5 w-5" />,
    },
    {
      name: "Analytics",
      section: "analytics",
      icon: <BarChart3 className="h-5 w-5" />,
    },
    {
      name: "Channel Management",
      section: "channels",
      icon: <Play className="h-5 w-5" />,
    },
    {
      name: "Music",
      section: "music",
      icon: <Music className="h-5 w-5" />,
    },
    {
      name: "Balance",
      section: "balance",
      icon: <Wallet className="h-5 w-5" />,
    },
    {
      name: "Digital Rights",
      section: "rights",
      icon: <Shield className="h-5 w-5" />,
    },
    {
      name: "Global Distribution",
      section: "distribution",
      icon: <Globe className="h-5 w-5" />,
    },
  ];

  const userStats = {
    joinDate: new Date(user?.created_at || Date.now()).toLocaleDateString(),
    lastLogin: new Date(
      user?.last_sign_in_at || Date.now()
    ).toLocaleDateString(),
    accountType: "Pro User",
    contentCount: 156,
  };

  const showNotification = (notification: any) => {
    Swal.fire({
      title: notification.title,
      text: notification.content,
      icon: "info",
      confirmButtonText: "Okay",
    });
  };

  if (isLoading) {
    return (
      <div className="min-h-screen bg-slate-900 flex items-center justify-center">
        <div className="flex flex-col items-center">
          <div className="animate-spin rounded-full h-12 w-12 border-t-2 border-b-2 border-indigo-500 mb-2"></div>
          <span className="text-white text-sm">Loading...</span>
        </div>
      </div>
    );
  }
  if (isRejected) {
    return (
      <div className="min-h-screen bg-slate-900 flex items-center justify-center p-4">
        <div className="max-w-xl w-full bg-slate-800 rounded-xl p-8 text-center relative overflow-hidden">
          <div className="absolute inset-0 bg-gradient-to-br from-red-500/5 via-slate-800/50 to-red-500/5"></div>
          <div className="relative z-10">
            <div className="w-20 h-20 mx-auto mb-6 rounded-full bg-red-500/20 flex items-center justify-center">
              <X className="w-10 h-10 text-red-500" />
            </div>
            <h2 className="text-2xl font-bold text-white mb-4">
              Application Rejected
            </h2>
            <p className="text-slate-300 mb-6">
              Unfortunately, your application has been rejected by admin.
            </p>
            {reason && (
              <div className="bg-slate-700/50 rounded-lg p-4 mb-6 text-left">
                <h3 className="text-white font-semibold mb-2">Reason:</h3>
                <ul className="text-slate-300 space-y-2 list-disc list-inside">
                  <li>{reason || "no reason"}</li>
                </ul>
              </div>
            )}
            <div className="flex flex-col sm:flex-row gap-4 justify-center">
              <button
                onClick={() => handleSignOut()}
                className="px-6 py-2 bg-indigo-600 text-white rounded-lg hover:bg-indigo-700 transition-colors duration-200"
              >
                Sign Out
              </button>
            </div>
          </div>
        </div>
      </div>
    );
  }
  return (
    <div className="min-h-screen bg-slate-900">
      {/* Onboarding Popup */}
      {showOnboarding && user && (
        <OnboardingPopup
          isOpen={showOnboarding}
          onClose={() => setShowOnboarding(false)}
          userId={user.id}
          userEmail={user.email || ""}
        />
      )}

      {/* Sidebar for desktop */}
      <div className="hidden md:fixed md:inset-y-0 md:flex md:w-64 md:flex-col">
        <div className="flex min-h-0 flex-1 flex-col bg-slate-800">
          <div className="flex flex-1 flex-col overflow-y-auto pt-5 pb-4">
            {/* User Profile Summary */}
            <div className="px-6 py-8 text-center">
              <div className="relative group">
                <div className="h-24 w-24 rounded-full bg-indigo-600 mx-auto mb-4 flex items-center justify-center text-white text-3xl font-bold relative overflow-hidden">
                  {profileImage ? (
                    <img
                      src={profileImage}
                      alt="Profile"
                      className="h-full w-full object-cover"
                    />
                  ) : (
                    user?.user_metadata?.full_name?.[0]?.toUpperCase() || (
                      <UserCircle className="h-16 w-16" />
                    )
                  )}

                  {/* Upload overlay */}
                  <label className="absolute inset-0 bg-black bg-opacity-50 flex items-center justify-center opacity-0 group-hover:opacity-100 cursor-pointer transition-opacity duration-200">
                    <input
                      type="file"
                      accept="image/*"
                      className="hidden"
                      onChange={handleImageUpload}
                      disabled={uploadingImage}
                    />
                    {uploadingImage ? (
                      <div className="animate-spin rounded-full h-6 w-6 border-2 border-white border-t-transparent" />
                    ) : (
                      <span className="text-white text-sm">Update</span>
                    )}
                  </label>
                </div>
              </div>

              <h2 className="text-xl font-bold text-white mb-1">
                Welcome,{" "}
                {user?.user_metadata?.full_name?.split(" ")[0] || "User"}!
              </h2>
            </div>

            <nav className="mt-5 flex-1 space-y-2 px-4">
              {navigationItems.map((item) => (
                <button
                  key={item.name}
                  onClick={() => setActiveSection(item.section)}
                  className="group flex items-center px-4 py-3 text-sm font-medium rounded-lg text-slate-300 hover:bg-slate-700 hover:text-white transition-all duration-300 relative overflow-hidden hover:shadow-lg hover:shadow-indigo-500/10 hover:scale-[1.02] hover:-translate-y-0.5"
                >
                  <div className="absolute inset-0 bg-gradient-to-r from-indigo-500/0 via-indigo-500/5 to-indigo-500/0 opacity-0 group-hover:opacity-100 transition-opacity duration-300"></div>
                  <div className="relative z-10 flex items-center">
                    <span className="transform transition-transform duration-300 group-hover:scale-110">
                      {item.icon}
                    </span>
                    <span className="ml-3 transform transition-transform duration-300 group-hover:translate-x-1">
                      {item.name}
                    </span>
                  </div>
                  {item.count && (
                    <span className="relative z-10 ml-auto bg-slate-900 py-0.5 px-2 rounded-full text-xs transform transition-all duration-300 group-hover:bg-indigo-900 group-hover:text-white">
                      {item.count}
                    </span>
                  )}
                </button>
              ))}
            </nav>
          </div>
        </div>
      </div>

      {/* Mobile menu */}
      <div className="md:hidden">
        <div className="fixed inset-0 z-40 flex">
          <div
            className={`fixed inset-0 bg-slate-600 bg-opacity-75 transition-opacity ease-in-out duration-300 ${
              isMobileMenuOpen ? "opacity-100" : "opacity-0 pointer-events-none"
            }`}
            onClick={() => setIsMobileMenuOpen(false)}
          />

          <div
            className={`relative flex w-full max-w-xs flex-1 flex-col bg-slate-800 pt-5 pb-4 transform transition ease-in-out duration-300 ${
              isMobileMenuOpen ? "translate-x-0" : "-translate-x-full"
            }`}
          >
            <div className="absolute top-1 right-0 -mr-14 p-1">
              <button
                type="button"
                className={`h-12 w-12 rounded-full flex items-center justify-center focus:outline-none focus:ring-2 focus:ring-white ${
                  isMobileMenuOpen ? "" : "hidden"
                }`}
                onClick={() => setIsMobileMenuOpen(false)}
              >
                <X className="h-6 w-6 text-white" />
              </button>
            </div>

            <div className="flex-shrink-0 flex items-center px-4">
              <img
                src="https://dlveiezovfooqbbfzfmo.supabase.co/storage/v1/object/public/Images//mtiger.png"
                alt="MediaTiger Logo"
                className="h-8 w-8"
              />
              <span className="ml-2 text-xl font-bold text-white">
                MediaTiger
              </span>
            </div>

            {/* Mobile User Profile Summary */}
            <div className="px-4 py-6 text-center">
              <div className="h-20 w-20 rounded-full bg-indigo-600 mx-auto mb-4 flex items-center justify-center text-white text-2xl font-bold">
                {user?.user_metadata?.full_name?.[0]?.toUpperCase() || (
                  <UserCircle className="h-12 w-12" />
                )}
              </div>
              <h2 className="text-lg font-bold text-white mb-1">
                Welcome,{" "}
                {user?.user_metadata?.full_name?.split(" ")[0] || "User"}!
              </h2>
              <p className="text-sm text-slate-400 mb-4">
                {userStats.accountType}
              </p>
            </div>

            <div className="mt-5 flex-1 h-0 overflow-y-auto">
              <nav className="px-2 space-y-1">
                {navigationItems.map((item) => (
                  <button
                    key={item.name}
                    onClick={() => {
                      setActiveSection(item.section);
                      setIsMobileMenuOpen(false);
                    }}
                    className="group flex items-center px-2 py-2 text-base font-medium rounded-md text-slate-300 hover:bg-slate-700 hover:text-white w-full"
                  >
                    {item.icon}
                    <span className="ml-3">{item.name}</span>
                    {item.count && (
                      <span className="ml-auto bg-slate-900 py-0.5 px-2 rounded-full text-xs">
                        {item.count}
                      </span>
                    )}
                  </button>
                ))}
              </nav>
            </div>
          </div>
        </div>
      </div>

      {/* Main content */}
      <div className="md:pl-64 flex flex-col flex-1">
        <div className="sticky top-0 z-10 bg-slate-800 pl-1 pt-1 sm:pl-3 sm:pt-3 md:hidden">
          <button
            type="button"
            className="inline-flex items-center justify-center rounded-md p-2 text-slate-400 hover:bg-slate-700 hover:text-white focus:outline-none focus:ring-2 focus:ring-inset focus:ring-white transition-colors duration-200"
            onClick={() => setIsMobileMenuOpen(true)}
          >
            <Menu className="h-6 w-6" />
          </button>
        </div>

        <main className="flex-1">
          <div className="py-6">
            {/* Background gradient effects */}
            <div className="absolute inset-0 bg-gradient-to-br from-indigo-500/5 via-purple-500/5 to-slate-500/5 pointer-events-none"></div>
            <div className="absolute -top-40 -right-40 w-80 h-80 bg-indigo-500/10 rounded-full filter blur-3xl pointer-events-none"></div>
            <div className="absolute -bottom-40 -left-40 w-80 h-80 bg-purple-500/10 rounded-full filter blur-3xl pointer-events-none"></div>

            <div className="max-w-7xl mx-auto px-4 sm:px-6 md:px-8 space-y-8">
              <div className="flex items-center justify-between">
                <h1
                  onMouseEnter={() => {
                    setShowNotifications(false);
                    setShowSettings(false);
                  }}
                  className="text-2xl font-semibold text-white w-full"
                >
                  {activeSection === "overview"
                    ? "Dashboard"
                    : activeSection === "channels"
                    ? "Channel Management"
                    : activeSection === "analytics"
                    ? "Analytics"
                    : activeSection === "rights"
                    ? "Digital Rights"
                    : activeSection === "music"
                    ? "Music Library"
                    : activeSection === "balance"
                    ? "Balance & Earnings"
                    : "Global Distribution"}
                </h1>
                <div className="flex items-center relative z-50">
                  {/* Added relative positioning and z-50 */}
                  <div
                    className="notifications-button mx-2 p-2 rounded-full text-slate-400 hover:text-white hover:bg-slate-700/50 transition-all duration-200 hover:scale-110 relative"
                    data-popover-target="notifications-popover"
                  >
                    <Bell
                      onClick={() => {
                        setShowNotifications((prev) => !prev);
                        setShowSettings(false); // Close settings when opening notifications
                      }}
                      className={`h-6 w-6 transition-all duration-300 ${
                        notifications.some((n) => !n.read)
                          ? "text-white animate-pulse filter drop-shadow-[0_0_15px_rgba(255,255,255,0.8)]"
                          : "text-slate-400"
                      }`}
                    />
                    {/* Notifications Dropdown with Apple-style Animation */}
                    {showNotifications &&
                      createPortal(
                        <div
                          className="dropdown fixed top-16 right-6 w-96 bg-slate-800/95 backdrop-blur-sm rounded-xl shadow-xl border border-slate-700/50 transform transition-all duration-500 z-50"
                          style={{
                            animation:
                              "slide-in-right 0.5s cubic-bezier(0.23, 1, 0.32, 1) forwards",
                            opacity: 0,
                            transform: "translateX(20px)",
                          }}
                        >
                          <div className="p-4 border-b border-slate-700 flex justify-between items-center">
                            <h3 className="text-white font-semibold">
                              Notifications
                            </h3>
                            <div className="flex gap-2">
                              <button
                                onClick={markAllAsRead}
                                className="text-xs text-slate-400 hover:text-white transition-colors"
                              >
                                Mark all as read
                              </button>
                              <button
                                onClick={clearNotifications}
                                className="text-xs text-slate-400 hover:text-white transition-colors"
                              >
                                Clear all
                              </button>
                            </div>
                          </div>
                          <div className="max-h-96 overflow-y-auto">
                            {notifications.length === 0 ? (
                              <div className="p-4 text-center text-slate-400">
                                No notifications
                              </div>
                            ) : (
                              notifications.map((notification) => (
                                <div
                                  key={notification.id}
                                  className={`p-4 border-b border-slate-700 hover:bg-slate-700/50 transition-all duration-300 ${
                                    !notification.read ? "bg-indigo-500/5" : ""
                                  }`}
                                >
                                  <h4 className="text-white font-medium">
                                    {notification.title}
                                  </h4>
                                  <p className="text-slate-400 text-sm mt-1">
                                    {notification.content}
                                  </p>
                                  <p className="text-slate-500 text-xs mt-2">
                                    {notification.time}
                                  </p>
                                </div>
                              ))
                            )}
                          </div>
                        </div>,
                        document.body
                      )}
                    {/* Add this CSS to your global styles or component */}
                    <style jsx>{`
                      @keyframes slide-in-right {
                        0% {
                          opacity: 0;
                          transform: translateX(20px);
                        }
                        100% {
                          opacity: 1;
                          transform: translateX(0);
                        }
                      }
                    `}</style>
                  </div>
                  <div
                    className="settings-button p-2 mr-2 rounded-full text-slate-400 hover:text-white hover:bg-slate-700/50 transition-all duration-200 hover:scale-110 relative"
                    onMouseEnter={() => {
                      setShowNotifications(false);
                    }}
                    onClick={() => {
                      setShowSettings(!showSettings);
                      setShowNotifications(false);
                    }}
                  >
                    <Settings className="h-6 w-6" />

                    {/* Settings Dropdown */}
                    {showSettings && (
                      <div className="settings-dropdown absolute right-0 top-full mt-2 w-80 bg-slate-800/95 backdrop-blur-sm rounded-xl shadow-xl border border-slate-700">
                        <div className="p-4 border-b border-slate-700">
                          <h3 className="text-white font-semibold">Settings</h3>
                        </div>
                        <div className="p-4 space-y-4">
                          {/* Profile Section */}
                          <div className="space-y-3">
                            <div className="flex items-center justify-between">
                              <span className="text-slate-400">Name</span>
                              <span className="text-white">
                                {user?.user_metadata?.full_name}
                              </span>
                            </div>
                            <div className="flex items-center justify-between">
                              <span className="text-slate-400">Email</span>
                              <span className="text-white">{user?.email}</span>
                            </div>
                            <button className="w-full text-left text-indigo-400 hover:text-indigo-300 transition-colors">
                              Change Password
                            </button>
                          </div>

                          <div className="border-t border-slate-700 pt-4">
                            <h4 className="text-white font-medium mb-3">
                              Security
                            </h4>
                            <div className="flex items-center justify-between">
                              <span className="text-slate-400">
                                Two-Factor Authentication
                              </span>
                              <button className="text-indigo-400 hover:text-indigo-300 transition-colors">
                                Enable
                              </button>
                            </div>
                          </div>

                          <div className="border-t border-slate-700 pt-4">
                            <h4 className="text-white font-medium mb-3">
                              Preferences
                            </h4>
                            <div className="space-y-3">
                              <div className="flex items-center justify-between">
                                <span className="text-slate-400">Language</span>
                                <select className="bg-slate-700 text-white rounded-md px-2 py-1 text-sm">
                                  <option>English</option>
                                  <option>Spanish</option>
                                  <option>French</option>
                                </select>
                              </div>
                              <div className="flex items-center justify-between">
                                <span className="text-slate-400">Timezone</span>
                                <select className="bg-slate-700 text-white rounded-md px-2 py-1 text-sm">
                                  <option>UTC</option>
                                  <option>EST</option>
                                  <option>PST</option>
                                </select>
                              </div>
                            </div>
                          </div>

                          <div className="border-t border-slate-700 pt-4">
                            <button
                              onClick={handleSignOut}
                              className="w-full flex items-center justify-center px-4 py-2 text-sm font-medium text-white bg-red-600 rounded-lg hover:bg-red-700 transition-colors"
                            >
                              <LogOut className="h-4 w-4 mr-2" />
                              Sign Out
                            </button>
                          </div>
                        </div>
                      </div>
                    )}
                  </div>
                  <Link
                    onMouseEnter={() => {
                      setShowNotifications(false);
                      setShowSettings(false);
                    }}
                    to="/messages"
                    className="p-2 rounded-full text-slate-400 hover:text-white hover:bg-slate-700/50 transition-all duration-200 hover:scale-110"
                  >
                    <MessageSquare
                      className={`h-6 w-6 transition-all duration-300 ${
                        hasUnreadMessages
                          ? "text-white animate-pulse filter drop-shadow-[0_0_15px_rgba(255,255,255,0.8)]"
                          : "text-slate-400"
                      }`}
                    />
                  </Link>
                </div>
              </div>

              {/* Main Content Area */}
              {activeSection === "overview" && (
                <div className="cards-dashboard grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4 relative z-[1]">
                  {/* Views Card */}
                  <div className="bg-slate-800/90 backdrop-blur-sm rounded-xl p-6 border border-slate-700/50 shadow-xl hover:shadow-indigo-500/10 transform hover:scale-105 transition-all duration-300 relative overflow-hidden">
                    <div className="absolute inset-0 bg-gradient-to-br from-indigo-500/5 via-purple-500/5 to-indigo-500/5 opacity-50"></div>
                    <div className="flex items-center">
                      <div className="p-3 rounded-full bg-gradient-to-br from-indigo-500/20 to-purple-500/20 group-hover:from-indigo-500/30 group-hover:to-purple-500/30 transition-all duration-300">
                        <Eye className="h-8 w-8 text-indigo-500" />
                      </div>
                      <div className="ml-4">
                        <p className="text-sm font-medium text-slate-400">
                          {new Date().toLocaleString("default", {
                            month: "long",
                          })}{" "}
                          Views
                        </p>
                        <p className="text-2xl font-semibold text-white">
                          {monthlyViews.toLocaleString()}
                        </p>
                      </div>
                    </div>
                  </div>

                  {/* Channels Card */}
                  <div className="bg-slate-800/90 backdrop-blur-sm rounded-xl p-6 border border-slate-700/50 shadow-xl hover:shadow-green-500/10 transform hover:scale-105 transition-all duration-300 relative overflow-hidden">
                    <div className="absolute inset-0 bg-gradient-to-br from-green-500/5 via-emerald-500/5 to-green-500/5 opacity-50"></div>
                    <div className="flex items-center">
                      <div className="p-3 rounded-full bg-gradient-to-br from-green-500/20 to-emerald-500/20 group-hover:from-green-500/30 group-hover:to-emerald-500/30 transition-all duration-300">
                        <Play className="h-8 w-8 text-green-500" />
                      </div>
                      <div className="ml-4">
                        <p className="text-sm font-medium text-slate-400">
                          Active Channels
                        </p>
                        <p className="text-2xl font-semibold text-white">
                          {linkedChannels}
                        </p>
                      </div>
                    </div>
                  </div>

                  {/* Rights Card */}
                  <div className="bg-slate-800/90 backdrop-blur-sm rounded-xl p-6 border border-slate-700/50 shadow-xl hover:shadow-purple-500/10 transform hover:scale-105 transition-all duration-300 relative overflow-hidden">
                    <div className="absolute inset-0 bg-gradient-to-br from-purple-500/5 via-pink-500/5 to-purple-500/5 opacity-50"></div>
                    <div className="flex items-center">
                      <div className="flex-shrink-0 p-3 rounded-full bg-gradient-to-br from-purple-500/20 to-pink-500/20 group-hover:from-purple-500/30 group-hover:to-pink-500/30 transition-all duration-300">
                        <Shield className="h-8 w-8 text-purple-500" />
                      </div>
                      <div className="ml-4 min-w-0 flex-1">
                        <p className="text-sm font-medium text-slate-400">
                          Revenue
                        </p>
                        <p className="text-2xl font-semibold text-white whitespace-nowrap">
                          $156K
                        </p>
                      </div>
                    </div>
                  </div>

                  {/* Distribution Card */}
                  <div className="bg-slate-800/90 backdrop-blur-sm rounded-xl p-6 border border-slate-700/50 shadow-xl hover:shadow-blue-500/10 transform hover:scale-105 transition-all duration-300 relative overflow-hidden">
                    <div className="absolute inset-0 bg-gradient-to-br from-blue-500/5 via-cyan-500/5 to-blue-500/5 opacity-50"></div>
                    <div className="flex items-center">
                      <div className="p-3 rounded-full bg-gradient-to-br from-blue-500/20 to-cyan-500/20 group-hover:from-blue-500/30 group-hover:to-cyan-500/30 transition-all duration-300">
                        <Globe className="h-8 w-8 text-blue-500" />
                      </div>
                      <div className="ml-4">
                        <p className="text-sm font-medium text-slate-400">
                          Global Reach
                        </p>
                        <p className="text-2xl font-semibold text-white">48M</p>
                      </div>
                    </div>
                  </div>

                  {/* Realtime Views Section */}
                  <div className="col-span-full bg-slate-800/90 backdrop-blur-sm rounded-xl p-6 border border-slate-700/50">
                    <h3 className="text-lg font-semibold text-white mb-4 flex items-center">
                      <Activity className="h-5 w-5 text-indigo-400 mr-2 animate-pulse" />
                      Realtime Performance
                    </h3>
                    <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                      <div className="realtime-card wave-animation bg-gradient-to-br from-slate-700/50 via-slate-700/40 to-slate-700/50 rounded-lg p-4 border border-slate-600/30">
                        <div className="flex items-center justify-between mb-2">
                          <span className="text-slate-300">Current Views</span>
                          <Clock className="h-4 w-4 text-indigo-400 animate-pulse" />
                        </div>
                        <p className="text-2xl font-bold text-white">
                          {formatNumber(realtimeViews.current)}
                        </p>
                        <p className="text-sm text-slate-400">
                          Active viewers right now
                        </p>
                      </div>
                      <div className="realtime-card wave-animation bg-gradient-to-br from-slate-700/50 via-slate-700/40 to-slate-700/50 rounded-lg p-4 border border-slate-600/30">
                        <div className="flex items-center justify-between mb-2">
                          <span className="text-slate-300">Last 24 Hours</span>
                          <Eye className="h-4 w-4 text-green-400 animate-pulse" />
                        </div>
                        <p className="text-2xl font-bold text-white">
                          {formatNumber(realtimeViews.last24h)}
                        </p>
                        <p className="text-sm text-slate-400">
                          Total views in past 24h
                        </p>
                      </div>
                      <div className="realtime-card wave-animation bg-gradient-to-br from-slate-700/50 via-slate-700/40 to-slate-700/50 rounded-lg p-4 border border-slate-600/30">
                        <div className="flex items-center justify-between mb-2">
                          <span className="text-slate-300">Last 48 Hours</span>
                          <BarChart2 className="h-4 w-4 text-blue-400 animate-pulse" />
                        </div>
                        <p className="text-2xl font-bold text-white">
                          {formatNumber(realtimeViews.last48h)}
                        </p>
                        <p className="text-sm text-slate-400">
                          Total views in past 48h
                        </p>
                      </div>
                    </div>
                  </div>

                  {/* Goals Section */}
                  <div className="col-span-full md:col-span-2 bg-slate-800/90 backdrop-blur-sm rounded-xl p-6 border border-slate-700/50">
                    <h3 className="text-lg font-semibold text-white mb-4 flex items-center">
                      <Target className="h-5 w-5 text-indigo-400 mr-2" />
                      Monthly Goals
                    </h3>
                    <div className="space-y-6">
                      {goals.map((goal) => {
                        const percentage = Math.round(
                          (goal.current / goal.target) * 100
                        );
                        return (
                          <div key={goal.id} className="space-y-2">
                            <div className="flex justify-between items-center">
                              <span className="text-slate-300">
                                {goal.title}
                              </span>
                              <span className="text-slate-400">
                                {formatNumber(goal.current)} /{" "}
                                {formatNumber(goal.target)} {goal.unit}
                              </span>
                            </div>
                            <div className="h-2 bg-slate-700 rounded-full overflow-hidden">
                              <div
                                className={`h-full bg-${goal.color}-500 rounded-full transition-all duration-500`}
                                style={{ width: `${percentage}%` }}
                              ></div>
                            </div>
                            <div className="text-sm text-slate-400 text-right">
                              {percentage}% Complete
                            </div>
                          </div>
                        );
                      })}
                    </div>
                  </div>

                  {/* Activity Feed */}
                  <div className="col-span-full md:col-span-2 bg-slate-800/90 backdrop-blur-sm rounded-xl p-6 border border-slate-700/50">
                    <h3 className="text-lg font-semibold text-white mb-4 flex items-center">
                      <Activity className="h-5 w-5 text-indigo-400 mr-2" />
                      Recent Activity
                    </h3>
                    <div className="space-y-4 max-h-[400px] overflow-y-auto pr-2">
                      {recentActivity.map((activity) => (
                        <div
                          key={activity.id}
                          className="bg-slate-700/50 rounded-lg p-4 flex items-start space-x-4"
                        >
                          <div
                            className={`p-2 rounded-full ${
                              activity.type === "view"
                                ? "bg-blue-500/20"
                                : activity.type === "subscriber"
                                ? "bg-green-500/20"
                                : activity.type === "revenue"
                                ? "bg-purple-500/20"
                                : "bg-indigo-500/20"
                            }`}
                          >
                            {activity.type === "view" && (
                              <Eye className="h-5 w-5 text-blue-400" />
                            )}
                            {activity.type === "subscriber" && (
                              <UsersIcon className="h-5 w-5 text-green-400" />
                            )}
                            {activity.type === "revenue" && (
                              <DollarSign className="h-5 w-5 text-purple-400" />
                            )}
                            {activity.type === "milestone" && (
                              <Award className="h-5 w-5 text-indigo-400" />
                            )}
                          </div>
                          <div className="flex-1">
                            <div className="flex justify-between items-start">
                              <h4 className="text-white font-medium">
                                {activity.title}
                              </h4>
                              <span className="text-sm text-slate-400">
                                {formatRelativeTime(activity.timestamp)}
                              </span>
                            </div>
                            <p className="text-slate-300 text-sm mt-1">
                              {activity.description}
                            </p>
                            {activity.metadata?.trend && (
                              <div
                                className={`flex items-center mt-2 ${
                                  activity.metadata.trend === "up"
                                    ? "text-green-400"
                                    : "text-red-400"
                                }`}
                              >
                                {activity.metadata.trend === "up" ? (
                                  <TrendingUp className="h-4 w-4 mr-1" />
                                ) : (
                                  <TrendingDown className="h-4 w-4 mr-1" />
                                )}
                                <span className="text-sm">
                                  {activity.metadata.amount}%{" "}
                                  {activity.metadata.trend === "up"
                                    ? "increase"
                                    : "decrease"}
                                </span>
                              </div>
                            )}
                          </div>
                        </div>
                      ))}
                    </div>
                  </div>

                  {/* Performance Trends */}
                  <div className="col-span-full bg-slate-800/90 backdrop-blur-sm rounded-xl p-6 border border-slate-700/50">
                    <h3 className="text-lg font-semibold text-white mb-4 flex items-center">
                      <LineChart className="h-5 w-5 text-indigo-400 mr-2" />
                      Performance Trends
                    </h3>
                    <div className="h-[300px] w-full">
                      <Line
                        data={{
                          labels: performanceData.labels,
                          datasets: [
                            {
                              label: "Views",
                              data: performanceData.views,
                              borderColor: "rgb(99, 102, 241)",
                              backgroundColor: "rgba(99, 102, 241, 0.1)",
                              tension: 0.4,
                              fill: true,
                            },
                            {
                              label: "Engagement Rate",
                              data: performanceData.engagement,
                              borderColor: "rgb(168, 85, 247)",
                              backgroundColor: "rgba(168, 85, 247, 0.1)",
                              tension: 0.4,
                              fill: true,
                            },
                            {
                              label: "Revenue",
                              data: performanceData.revenue,
                              borderColor: "rgb(34, 197, 94)",
                              backgroundColor: "rgba(34, 197, 94, 0.1)",
                              tension: 0.4,
                              fill: true,
                            },
                          ],
                        }}
                        options={{
                          responsive: true,
                          maintainAspectRatio: false,
                          interaction: {
                            intersect: false,
                            mode: "index",
                          },
                          scales: {
                            y: {
                              grid: {
                                color: "rgba(148, 163, 184, 0.1)",
                              },
                              ticks: {
                                color: "rgb(148, 163, 184)",
                              },
                            },
                            x: {
                              grid: {
                                color: "rgba(148, 163, 184, 0.1)",
                              },
                              ticks: {
                                color: "rgb(148, 163, 184)",
                              },
                            },
                          },
                          plugins: {
                            legend: {
                              labels: {
                                color: "rgb(148, 163, 184)",
                              },
                            },
                            tooltip: {
                              backgroundColor: "rgba(30, 41, 59, 0.8)",
                              titleColor: "rgb(255, 255, 255)",
                              bodyColor: "rgb(148, 163, 184)",
                              borderColor: "rgba(148, 163, 184, 0.2)",
                              borderWidth: 1,
                            },
                          },
                        }}
                      />
                    </div>
                  </div>
                </div>
              )}
              {activeSection == "channels" && <ChannelManagement />}
              {activeSection !== "overview" && activeSection !== "channels" && (
                <div className="bg-slate-800 rounded-xl p-12 text-center">
                  <h3 className="text-xl font-semibold text-white mb-2">
                    Coming Soon
                  </h3>
                  <p className="text-slate-400">
                    This section is currently under development
                  </p>
                </div>
              )}
            </div>
          </div>
        </main>
      </div>
    </div>
  );
}
