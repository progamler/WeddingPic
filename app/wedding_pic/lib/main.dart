import 'dart:typed_data';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'dart:convert';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:webdav_client/webdav_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Check if configuration is passed via URL parameters
  if (kIsWeb) {
    await _checkForConfigInUrl();
  }

  runApp(
    MaterialApp(
      theme: ThemeData.dark(),
      home: kIsWeb ? WebCameraScreen() : CameraScreen(),
    ),
  );
}

Future<void> _checkForConfigInUrl() async {
  try {
    final uri = Uri.parse(html.window.location.href);
    final configParam = uri.queryParameters['config'];
    
    if (configParam != null) {
      final configJson = utf8.decode(base64Decode(configParam));
      final config = WebDAVConfig.fromJson(jsonDecode(configJson));
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('webdav_url', config.webdavUrl);
      await prefs.setString('webdav_user', config.webdavUser);
      await prefs.setString('webdav_password', config.webdavPassword);
    }
  } catch (e) {
    print('Error loading configuration from URL: $e');
  }
}

// A screen that initializes cameras and shows the camera interface
class CameraScreen extends StatefulWidget {
  @override
  _CameraScreenState createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  List<CameraDescription>? cameras;
  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _initializeCameras();
  }

  Future<void> _initializeCameras() async {
    try {
      final cameraList = await availableCameras();
      if (cameraList.isEmpty) {
        setState(() {
          errorMessage = 'No cameras found on this device';
          isLoading = false;
        });
        return;
      }
      
      setState(() {
        cameras = cameraList;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        errorMessage = 'Failed to initialize cameras: $e';
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Wedding Pic')),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 20),
              Text('Initializing cameras...'),
            ],
          ),
        ),
      );
    }

    if (errorMessage != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Wedding Pic')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error, size: 64, color: Colors.red),
              SizedBox(height: 20),
              Text(
                errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
              SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    isLoading = true;
                    errorMessage = null;
                  });
                  _initializeCameras();
                },
                child: Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return TakePictureScreen(camera: cameras!.first);
  }
}

// A screen that allows users to take a picture using a given camera.
class TakePictureScreen extends StatefulWidget {
  const TakePictureScreen({
    super.key,
    required this.camera,
  });

  final CameraDescription camera;

  @override
  TakePictureScreenState createState() => TakePictureScreenState();
}

class TakePictureScreenState extends State<TakePictureScreen> {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;

  @override
  void initState() {
    super.initState();
    // To display the current output from the Camera,
    // create a CameraController.
    _controller = CameraController(
      // Get a specific camera from the list of available cameras.
      widget.camera,
      // Define the resolution to use.
      ResolutionPreset.medium,
    );

    // Next, initialize the controller. This returns a Future.
    _initializeControllerFuture = _controller.initialize();
  }

  @override
  void dispose() {
    // Dispose of the controller when the widget is disposed.
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Take a picture')),
      // You must wait until the controller is initialized before displaying the
      // camera preview. Use a FutureBuilder to display a loading spinner until the
      // controller has finished initializing.
      body: FutureBuilder<void>(
        future: _initializeControllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            if (snapshot.hasError) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error, size: 64, color: Colors.red),
                    SizedBox(height: 20),
                    Text(
                      'Camera Error: ${snapshot.error}',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16),
                    ),
                    SizedBox(height: 20),
                    Text(
                      'Camera may not be supported in web browsers. Try using a mobile device or desktop app.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                  ],
                ),
              );
            }
            // If the Future is complete, display the preview.
            return Center(
              child: Container(
                width: 640,
                height: 480,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                ),
                child: CameraPreview(_controller),
              ),
            );
          } else {
            // Otherwise, display a loading indicator.
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 20),
                  Text('Initializing camera...'),
                ],
              ),
            );
          }
        },
      ),
      floatingActionButton: FloatingActionButton(
        // Provide an onPressed callback.
        onPressed: () async {
          // Take the Picture in a try / catch block. If anything goes wrong,
          // catch the error.
          try {
            // Ensure that the camera is initialized.
            await _initializeControllerFuture;

            // Attempt to take a picture and get the file `image`
            // where it was saved.
            final image = await _controller.takePicture();

            if (!mounted) return;

            // If the picture was taken, display it on a new screen.
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => DisplayPictureScreen(
                  // Pass the XFile to the DisplayPictureScreen widget.
                  image: image,
                ),
              ),
            );
          } catch (e) {
            // If an error occurs, log the error to the console.
            print(e);
          }
        },
        child: const Icon(Icons.camera_alt),
      ),
    );
  }
}

// A widget that displays the picture taken by the user.
class DisplayPictureScreen extends StatelessWidget {
  final XFile image;

  const DisplayPictureScreen({super.key, required this.image});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Display the Picture')),
      body: Column(
        children: [
          FutureBuilder<Uint8List>(
            future: image.readAsBytes(),
            builder: (BuildContext context, AsyncSnapshot<Uint8List> snapshot) {
              if (snapshot.connectionState == ConnectionState.done &&
                  snapshot.hasData) {
                return Image.memory(snapshot.data!);
              } else {
                return const Center(child: CircularProgressIndicator());
              }
            },
          ),
          ElevatedButton(
            onPressed: () async {
              // Upload the image to WebDAV server
              final client = newClient(
                'YOUR_WEBDAV_URL',
                user: 'YOUR_USERNAME',
                password: 'YOUR_PASSWORD',
              );
              client.setHeaders({'accept-charset': 'utf-8'});
              final bytes = await image.readAsBytes();
              final fileName = image.name;
              await client.write(
                fileName,
                bytes,
              );
              final uploadLink = 'YOUR_WEBDAV_URL/$fileName';

              if (!context.mounted) return;
              // Show QR code with the upload link
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => ShareScreen(
                    uploadLink: uploadLink,
                  ),
                ),
              );
            },
            child: const Text('Upload Picture'),
          )
        ],
      ),
    );
  }
}

class ShareScreen extends StatelessWidget {
  final String uploadLink;

  const ShareScreen({super.key, required this.uploadLink});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Share')),
      body: Center(
        child: QrImageView(
          data: uploadLink,
          version: QrVersions.auto,
          size: 200.0,
        ),
      ),
    );
  }
}

// Web-specific camera implementation using HTML5 getUserMedia
class WebCameraScreen extends StatefulWidget {
  @override
  _WebCameraScreenState createState() => _WebCameraScreenState();
}

class _WebCameraScreenState extends State<WebCameraScreen> {
  html.VideoElement? videoElement;
  html.MediaStream? mediaStream;
  bool isLoading = true;
  String? errorMessage;
  String videoViewType = 'camera-video-${DateTime.now().millisecondsSinceEpoch}';

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      // Create video element
      videoElement = html.VideoElement()
        ..autoplay = true
        ..muted = true
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.objectFit = 'cover';

      // Register the video element with Flutter's platform view registry
      ui_web.platformViewRegistry.registerViewFactory(
        videoViewType,
        (int viewId) => videoElement!,
      );

      // Request camera access
      final constraints = {
        'video': {
          'width': {'ideal': 1280},
          'height': {'ideal': 720},
          'facingMode': 'user'
        },
        'audio': false
      };

      mediaStream = await html.window.navigator.mediaDevices!.getUserMedia(constraints);
      videoElement!.srcObject = mediaStream;

      setState(() {
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        errorMessage = 'Failed to access camera: $e';
        isLoading = false;
      });
    }
  }

  Future<void> _takePicture() async {
    if (videoElement == null) return;

    try {
      // Create canvas to capture the video frame
      final canvas = html.CanvasElement(
        width: videoElement!.videoWidth,
        height: videoElement!.videoHeight,
      );
      
      final canvasContext = canvas.context2D;
      canvasContext.drawImageScaled(videoElement!, 0, 0, canvas.width!, canvas.height!);
      
      // Convert canvas to blob
      final blob = await canvas.toBlob('image/png');
      final bytes = await _blobToUint8List(blob);
      
      if (!mounted) return;
      
      // Navigate to display screen
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => WebDisplayPictureScreen(imageBytes: bytes),
        ),
      );
    } catch (e) {
      print('Error taking picture: $e');
    }
  }

  Future<Uint8List> _blobToUint8List(html.Blob blob) async {
    final reader = html.FileReader();
    reader.readAsArrayBuffer(blob);
    await reader.onLoad.first;
    return reader.result as Uint8List;
  }

  @override
  void dispose() {
    mediaStream?.getTracks().forEach((track) => track.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Wedding Pic')),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 20),
              Text('Requesting camera access...'),
              SizedBox(height: 10),
              Text(
                'Please allow camera access when prompted by your browser.',
                style: TextStyle(fontSize: 14, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    if (errorMessage != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Wedding Pic')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error, size: 64, color: Colors.red),
              SizedBox(height: 20),
              Text(
                errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
              SizedBox(height: 20),
              Text(
                'Make sure to allow camera access in your browser settings.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    isLoading = true;
                    errorMessage = null;
                  });
                  _initializeCamera();
                },
                child: Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Wedding Pic'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => SettingsScreen(),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.qr_code),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => AppQRScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: Center(
        child: Container(
          width: 640,
          height: 480,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey),
          ),
          child: HtmlElementView(viewType: videoViewType),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _takePicture,
        child: const Icon(Icons.camera_alt),
      ),
    );
  }
}

class WebDisplayPictureScreen extends StatelessWidget {
  final Uint8List imageBytes;

  const WebDisplayPictureScreen({super.key, required this.imageBytes});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Display the Picture')),
      body: Column(
        children: [
          Expanded(
            child: Image.memory(
              imageBytes,
              fit: BoxFit.contain,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: ElevatedButton(
              onPressed: () async {
                // Upload the image to WebDAV server
                try {
                  final prefs = await SharedPreferences.getInstance();
                  final webdavUrl = prefs.getString('webdav_url') ?? '';
                  final webdavUser = prefs.getString('webdav_user') ?? '';
                  final webdavPassword = prefs.getString('webdav_password') ?? '';
                  
                  if (webdavUrl.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please configure WebDAV settings first')),
                    );
                    return;
                  }
                  
                  final client = newClient(
                    webdavUrl,
                    user: webdavUser,
                    password: webdavPassword,
                  );
                  client.setHeaders({'accept-charset': 'utf-8'});
                  final fileName = 'photo_${DateTime.now().millisecondsSinceEpoch}.png';
                  await client.write(fileName, imageBytes);
                  final uploadLink = '$webdavUrl/$fileName';

                  if (!context.mounted) return;
                  // Show QR code with the upload link
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => ShareScreen(uploadLink: uploadLink),
                    ),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Upload failed: $e')),
                  );
                }
              },
              child: const Text('Upload Picture'),
            ),
          ),
        ],
      ),
    );
  }
}

// Settings screen for WebDAV configuration
class SettingsScreen extends StatefulWidget {
  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _urlController = TextEditingController();
  final _userController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _urlController.text = prefs.getString('webdav_url') ?? '';
      _userController.text = prefs.getString('webdav_user') ?? '';
      _passwordController.text = prefs.getString('webdav_password') ?? '';
    });
  }

  Future<void> _saveSettings() async {
    if (_formKey.currentState!.validate()) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('webdav_url', _urlController.text);
      await prefs.setString('webdav_user', _userController.text);
      await prefs.setString('webdav_password', _passwordController.text);
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved successfully')),
      );
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('WebDAV Settings')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _urlController,
                decoration: const InputDecoration(
                  labelText: 'WebDAV URL',
                  hintText: 'https://your-server.com/webdav',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter WebDAV URL';
                  }
                  final uri = Uri.tryParse(value);
                  if (uri == null || !uri.hasAbsolutePath) {
                    return 'Please enter a valid URL';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _userController,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter username';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter password';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _saveSettings,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                ),
                child: const Text('Save Settings'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _urlController.dispose();
    _userController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}

// QR Code screen for sharing app and configuration
class AppQRScreen extends StatefulWidget {
  @override
  _AppQRScreenState createState() => _AppQRScreenState();
}

class _AppQRScreenState extends State<AppQRScreen> {
  String qrData = '';

  @override
  void initState() {
    super.initState();
    _generateQRData();
  }

  Future<void> _generateQRData() async {
    final prefs = await SharedPreferences.getInstance();
    final currentUrl = html.window.location.href.split('?')[0]; // Remove existing query params
    
    final config = WebDAVConfig(
      appUrl: currentUrl,
      webdavUrl: prefs.getString('webdav_url') ?? '',
      webdavUser: prefs.getString('webdav_user') ?? '',
      webdavPassword: prefs.getString('webdav_password') ?? '',
    );
    
    // Encode config as base64 to include in URL
    final configJson = jsonEncode(config.toJson());
    final configBase64 = base64Encode(utf8.encode(configJson));
    final urlWithConfig = '$currentUrl?config=$configBase64';
    
    setState(() {
      qrData = urlWithConfig;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Share App')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Scan this QR code to access the app with current settings',
              style: TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            if (qrData.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: QrImageView(
                  data: qrData,
                  version: QrVersions.auto,
                  size: 300.0,
                  backgroundColor: Colors.white,
                ),
              ),
            const SizedBox(height: 20),
            const Text(
              'This QR code contains the app URL and WebDAV configuration',
              style: TextStyle(fontSize: 14, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _generateQRData,
              child: const Text('Refresh QR Code'),
            ),
          ],
        ),
      ),
    );
  }
}

// Data class for WebDAV configuration
class WebDAVConfig {
  final String appUrl;
  final String webdavUrl;
  final String webdavUser;
  final String webdavPassword;

  WebDAVConfig({
    required this.appUrl,
    required this.webdavUrl,
    required this.webdavUser,
    required this.webdavPassword,
  });

  Map<String, dynamic> toJson() {
    return {
      'appUrl': appUrl,
      'webdavUrl': webdavUrl,
      'webdavUser': webdavUser,
      'webdavPassword': webdavPassword,
    };
  }

  factory WebDAVConfig.fromJson(Map<String, dynamic> json) {
    return WebDAVConfig(
      appUrl: json['appUrl'] ?? '',
      webdavUrl: json['webdavUrl'] ?? '',
      webdavUser: json['webdavUser'] ?? '',
      webdavPassword: json['webdavPassword'] ?? '',
    );
  }
}
