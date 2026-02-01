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
          return Scaffold(
            backgroundColor: const Color(0xFF0F172A),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                   const SizedBox(height: 20),
                   Image.asset(
                     'assets/thanima_logo.jpg',
                     width: 120,
                     height: 120,
                     errorBuilder: (c, o, s) => const Icon(Icons.event, size: 80, color: Colors.purple),
                   ),
                   const SizedBox(height: 24),
                   const Text(
                     'Thanima Attendance',
                     style: TextStyle(
                       color: Colors.white,
                       fontSize: 24,
                       fontWeight: FontWeight.bold,
                     ),
                   ),
                   const SizedBox(height: 8),
                   const Text(
                     'v1.2',
                     style: TextStyle(
                       color: Colors.grey,
                       fontSize: 16,
                     ),
                   ),
                   const SizedBox(height: 40),
                   const CircularProgressIndicator(color: Colors.purple),
                   const SizedBox(height: 40),
                   const Text(
                     'Thanima VIT Chennai',
                     style: TextStyle(
                       color: Colors.white70,
                       fontSize: 16,
                       fontWeight: FontWeight.w600,
                     ),
                     textAlign: TextAlign.center,
                   ),
                   const SizedBox(height: 4),
                   const Text(
                     'thanimavitc.site',
                     style: TextStyle(
                       color: Colors.blueAccent,
                       fontSize: 14,
                     ),
                     textAlign: TextAlign.center,
                   ),
                ],
              ),
            ),
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
