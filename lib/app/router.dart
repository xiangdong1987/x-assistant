import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../presentation/screens/shell/app_shell.dart';
import '../presentation/screens/dashboard/dashboard_screen.dart';
import '../presentation/screens/tasks/task_list_screen.dart';
import '../presentation/screens/tasks/task_detail_screen.dart';
import '../presentation/screens/tasks/add_task_screen.dart';
import '../presentation/screens/main/main_screen.dart';
import '../presentation/screens/history/history_screen.dart';
import '../presentation/screens/skills/skills_screen.dart';
import '../presentation/screens/skills/project_skills_screen.dart';
import '../presentation/screens/settings/settings_screen.dart';
import '../presentation/screens/settings/settings_or_proxy_config_screen.dart';
import '../presentation/screens/proxy_config/proxy_config_screen.dart';
import '../presentation/screens/capabilities/capabilities_screen.dart';
import '../presentation/screens/projects/projects_screen.dart';
import '../presentation/screens/projects/edit_project_screen.dart';
import '../presentation/screens/pairing/pairing_screen.dart';
import '../presentation/screens/splash/splash_screen.dart';
import '../presentation/screens/notifications/notifications_screen.dart';
import '../presentation/screens/agenda/agenda_screen.dart';
import '../presentation/screens/agenda/schedule_detail_screen.dart';
import '../../models/project_model.dart';
import '../../models/schedule_model.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/splash',
    routes: [
      // ── Shell (底部导航) ─────────────────────────────────────────────
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          // 首页 – 日历式主页
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/dashboard',
              name: 'dashboard',
              builder: (context, state) => const DashboardScreen(),
            ),
          ]),

          // 任务
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/tasks',
              name: 'tasks',
              builder: (context, state) => const TaskListScreen(),
            ),
          ]),

          // 日程
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/schedule',
              name: 'schedule',
              builder: (context, state) => const AgendaScreen(),
            ),
          ]),

          // 消息
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/notifications',
              name: 'notifications',
              builder: (context, state) => const NotificationsScreen(),
            ),
          ]),

          // 设置（配置、代理、连接等；macOS 无代理时先展示代理配置页）
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/config',
              name: 'settingsTab',
              builder: (context, state) => const SettingsOrProxyConfigScreen(),
            ),
          ]),
        ],
      ),

      // ── 全屏路由 (Shell 外) ────────────────────────────────────────
      GoRoute(
        path: '/agent',
        name: 'agent',
        builder: (context, state) => const MainScreen(),
      ),
      GoRoute(
        path: '/settings',
        name: 'settings',
        builder: (context, state) => SettingsScreen(
          showProxyPrompt: state.uri.queryParameters['open'] == 'proxy',
        ),
      ),
      GoRoute(
        path: '/proxy-config',
        name: 'proxyConfig',
        builder: (context, state) => const ProxyConfigScreen(),
      ),
      GoRoute(
        path: '/task/detail',
        name: 'taskDetail',
        builder: (context, state) =>
            TaskDetailScreen(taskId: state.extra as String),
      ),
      GoRoute(
        path: '/task/add',
        name: 'addTask',
        builder: (context, state) => const AddTaskScreen(),
      ),
      GoRoute(
        path: '/task/edit',
        name: 'editTask',
        builder: (context, state) =>
            AddTaskScreen(editTaskId: state.extra as String),
      ),
      GoRoute(
        path: '/capabilities',
        name: 'capabilities',
        builder: (context, state) => const CapabilitiesScreen(),
      ),
      GoRoute(
        path: '/projects',
        name: 'projects',
        builder: (context, state) => const ProjectsScreen(),
      ),
      GoRoute(
        path: '/project/add',
        name: 'addProject',
        builder: (context, state) => const EditProjectScreen(),
      ),
      GoRoute(
        path: '/project/edit',
        name: 'editProject',
        builder: (context, state) =>
            EditProjectScreen(project: state.extra as ProjectModel?),
      ),
      GoRoute(
        path: '/pairing',
        name: 'pairing',
        builder: (context, state) => const PairingScreen(),
      ),
      GoRoute(
        path: '/skills',
        name: 'skills',
        builder: (context, state) => const ProjectSkillsScreen(),
      ),
      GoRoute(
        path: '/skills/all',
        name: 'skillsAll',
        builder: (context, state) => const SkillsScreen(),
      ),
      GoRoute(
        path: '/history',
        name: 'history',
        builder: (context, state) => const HistoryScreen(),
      ),
      GoRoute(
        path: '/splash',
        name: 'splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/schedule/detail',
        name: 'scheduleDetail',
        builder: (context, state) =>
            ScheduleDetailScreen(item: state.extra as AgendaItem),
      ),
    ],
  );
});
