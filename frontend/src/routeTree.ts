import { createRootRoute, createRoute, createRouter } from '@tanstack/react-router'
import { RootLayout } from './routes/root'
import { HomePage } from './routes/home'
import { LoginPage } from './routes/login'
import { DashboardPage } from './routes/dashboard'
import { AssessmentPage } from './routes/assessment'
import { ProfilePage } from './routes/profile'

const rootRoute = createRootRoute({ component: RootLayout })

const indexRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/',
  component: HomePage,
})

const loginRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/login',
  component: LoginPage,
})

const dashboardRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/dashboard',
  component: DashboardPage,
})

const assessmentRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/assessment/$id',
  component: AssessmentPage,
})

const profileRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/profile/$userId',
  component: ProfilePage,
})

export const routeTree = rootRoute.addChildren([
  indexRoute,
  loginRoute,
  dashboardRoute,
  assessmentRoute,
  profileRoute,
])
