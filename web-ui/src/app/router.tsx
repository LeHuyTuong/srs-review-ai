import { createBrowserRouter, Navigate } from "react-router-dom"
import TeacherOnly from "@/app/TeacherOnly"
import AuthLayout from "@/layouts/AuthLayout"
import MobileAppLayout from "@/layouts/MobileAppLayout"
import LoginPage from "@/pages/auth/LoginPage"
import ClassDetailPage from "@/pages/classes/ClassDetailPage"
import ClassListPage from "@/pages/classes/ClassListPage"
import DashboardPage from "@/pages/dashboard/DashboardPage"
import ProjectDocumentsPage from "@/pages/documents/ProjectDocumentsPage"
import NotificationsPage from "@/pages/notifications/NotificationsPage"
import ProfilePage from "@/pages/profile/ProfilePage"
import ProjectDetailPage from "@/pages/projects/ProjectDetailPage"
import ProjectListPage from "@/pages/projects/ProjectListPage"
import AIReviewResultPage from "@/pages/reviews/AIReviewResultPage"
import ReviewHistoryPage from "@/pages/reviews/ReviewHistoryPage"
import ReviewDetailPage from "@/pages/reviews/ReviewDetailPage"
import ReviewListPage from "@/pages/reviews/ReviewListPage"
import VersionHistoryPage from "@/pages/reviews/VersionHistoryPage"

export const router = createBrowserRouter([
  {
    element: <AuthLayout />,
    children: [{ path: "login", element: <LoginPage /> }],
  },
  {
    path: "/",
    element: <MobileAppLayout />,
    children: [
      { index: true, element: <Navigate to="/dashboard" replace /> },
      { path: "dashboard", element: <DashboardPage /> },
      { path: "classes", element: <TeacherOnly><ClassListPage /></TeacherOnly> },
      { path: "classes/:classId", element: <TeacherOnly><ClassDetailPage /></TeacherOnly> },
      { path: "projects", element: <TeacherOnly><ProjectListPage /></TeacherOnly> },
      { path: "projects/:projectId", element: <TeacherOnly><ProjectDetailPage /></TeacherOnly> },
      { path: "projects/:projectId/documents", element: <TeacherOnly><ProjectDocumentsPage /></TeacherOnly> },
      { path: "reviews", element: <ReviewListPage /> },
      { path: "reviews/:reviewId", element: <ReviewDetailPage /> },
      { path: "reviews/:reviewId/ai-result", element: <AIReviewResultPage /> },
      { path: "reviews/:reviewId/versions", element: <VersionHistoryPage /> },
      { path: "reviews/:reviewId/history", element: <ReviewHistoryPage /> },
      { path: "notifications", element: <NotificationsPage /> },
      { path: "profile", element: <ProfilePage /> },
      { path: "*", element: <Navigate to="/dashboard" replace /> },
    ],
  },
])
