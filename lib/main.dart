import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'providers/auth_provider.dart';
import 'screens/login_screen.dart';
import 'screens/events_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Request camera permission on startup
  await Permission.camera.request();
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
      ],
      child: MaterialApp(
        title: 'Thanima Attendance',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primarySwatch: Colors.purple,
          scaffoldBackgroundColor: const Color(0xFF0F172A),
          colorScheme: ColorScheme.dark(
            primary: Colors.purple,
            secondary: Colors.pink,
            surface: const Color(0xFF1E293B),
            background: const Color(0xFF0F172A),
          ),
          useMaterial3: true,
          fontFamily: 'Inter', // Using default font for now
        ),
        home: const AuthWrapper(),
      ),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => 
      Provider.of<AuthProvider>(context, listen: false).checkAuth()
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, auth, child) {
        if (auth.isLoading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        
        if (auth.isAuthenticated) {
          return const EventsScreen();
        }
        
        return const LoginScreen();
      },
    );
  }
}
