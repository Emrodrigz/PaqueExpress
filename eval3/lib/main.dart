import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart'; 
import 'package:latlong2/latlong.dart';
import 'dart:typed_data'; 
import 'package:flutter/foundation.dart'; 

void main() => runApp(const MyApp());

const baseUrl = "http://127.0.0.1:8000"; 

final storage = const FlutterSecureStorage();

class ApiClient {
  final Dio dio = Dio(BaseOptions(baseUrl: baseUrl));

  ApiClient() {
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await storage.read(key: "token");
        if (token != null && token.isNotEmpty) {
          options.headers["Authorization"] = "Bearer $token";
        }
        handler.next(options);
      },
      onError: (e, handler) async {
        if (e.response?.statusCode == 401) {
          // Si el token expira o es inválido, borra y redirige
          await storage.delete(key: "token");
          // Nota: La redirección a LoginPage debe manejarse a nivel de widget, 
          // aquí solo se borra el token.
        }
        handler.next(e);
      },
    ));
  }
}

final api = ApiClient();

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: "Paquexpress",
        theme: ThemeData(primarySwatch: Colors.blue),
        home: const LoginPage(),
      );
}

// -----------------------------------------------------------------
// PÁGINA DE LOGIN
// -----------------------------------------------------------------

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final emailCtrl = TextEditingController();
  final passCtrl = TextEditingController();

  Future<void> login() async {
    try {
      final res = await api.dio.post(
        "/auth/login",
        data: {"username": emailCtrl.text.trim(), "password": passCtrl.text},
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      final token = res.data["access_token"];
      await storage.write(key: "token", value: token);

      // CAMBIO: Navegar a la página de listado de paquetes
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const ListarPaquetesPage()),
      );
    } on DioException catch (e) {
      String msg = e.response?.data.toString() ?? e.message ?? "Error de red desconocido";
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error de login: $msg")));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error inesperado: $e")));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text("Login Agente")),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            TextField(controller: emailCtrl, decoration: const InputDecoration(labelText: "Email")),
            TextField(controller: passCtrl, decoration: const InputDecoration(labelText: "Contraseña"), obscureText: true),
            const SizedBox(height: 20),
            ElevatedButton(onPressed: login, child: const Text("Ingresar")),
            TextButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterPage())),
              child: const Text("Registrarse"),
            ),
          ]),
        ),
      );
}

// -----------------------------------------------------------------
// PÁGINA DE REGISTRO
// -----------------------------------------------------------------

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});
  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final nombreCtrl = TextEditingController();
  final emailCtrl = TextEditingController();
  final passCtrl = TextEditingController();

  Future<void> registrar() async {
    try {
      await api.dio.post(
        "/auth/register",
        data: {"nombre": nombreCtrl.text, "email": emailCtrl.text.trim(), "password": passCtrl.text},
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Usuario registrado con éxito")));
      Navigator.pop(context);
    } on DioException catch (e) {
      String msg = e.response?.data.toString() ?? e.message ?? "Error de red desconocido";
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error de registro: $msg")));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text("Registro Agente")),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            TextField(controller: nombreCtrl, decoration: const InputDecoration(labelText: "Nombre")),
            TextField(controller: emailCtrl, decoration: const InputDecoration(labelText: "Email")),
            TextField(controller: passCtrl, decoration: const InputDecoration(labelText: "Contraseña"), obscureText: true),
            const SizedBox(height: 20),
            ElevatedButton(onPressed: registrar, child: const Text("Registrarse")),
          ]),
        ),
      );
}

// -----------------------------------------------------------------
// PÁGINA DE LISTADO DE PAQUETES (NUEVA)
// -----------------------------------------------------------------

class PaqueteItem {
  final int id;
  final String uid;
  final String direccion;

  PaqueteItem({required this.id, required this.uid, required this.direccion});
}

class ListarPaquetesPage extends StatefulWidget {
  const ListarPaquetesPage({super.key});
  @override
  State<ListarPaquetesPage> createState() => _ListarPaquetesPageState();
}

class _ListarPaquetesPageState extends State<ListarPaquetesPage> {
  List<PaqueteItem> paquetes = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _cargarPaquetes();
  }

  Future<void> _cargarPaquetes() async {
    try {
      final res = await api.dio.get("/paquetes/listado"); 
      setState(() {
        paquetes = (res.data as List)
            .map((json) => PaqueteItem(
                  id: json['id'],
                  uid: json['paquete_uid'],
                  direccion: json['direccion'],
                ))
            .toList();
        isLoading = false;
      });
    } on DioException catch (e) {
      String msg = e.response?.data.toString() ?? e.message ?? "Error de red desconocido";
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error cargando listado: $msg")));
      setState(() { isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text("Seleccionar Paquete")),
        body: isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView.builder(
                itemCount: paquetes.length,
                itemBuilder: (context, index) {
                  final paquete = paquetes[index];
                  return ListTile(
                    title: Text(paquete.uid),
                    subtitle: Text(paquete.direccion),
                    trailing: const Icon(Icons.arrow_forward_ios),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PaqueteMapaPage(paqueteId: paquete.id),
                        ),
                      );
                    },
                  );
                },
              ),
      );
}

// -----------------------------------------------------------------
// PÁGINA DE MAPA
// -----------------------------------------------------------------

class PaqueteMapaPage extends StatefulWidget {
  final int paqueteId;
  const PaqueteMapaPage({super.key, required this.paqueteId});
  @override
  State<PaqueteMapaPage> createState() => _PaqueteMapaPageState();
}

class _PaqueteMapaPageState extends State<PaqueteMapaPage> {
  LatLng? destino; 
  String direccion = "";
  Position? miPos;

  @override
  void initState() {
    super.initState();
    _cargarPaquete();
    _obtenerMiUbicacion();
  }

  Future<void> _cargarPaquete() async {
    try {
      final res = await api.dio.get("/paquetes/${widget.paqueteId}");
      setState(() {
        direccion = res.data["direccion"];
        destino = LatLng(res.data["lat"], res.data["lon"]); 
      });
    } on DioException catch (e) {
      String msg = e.response?.data.toString() ?? e.message ?? "Error de red desconocido";
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error cargando paquete: $msg")));
    }
  }

  Future<void> _obtenerMiUbicacion() async {
    try {
      await Geolocator.requestPermission();
      miPos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      setState(() {});
    } catch (e) {
      miPos = null;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text("Mapa de Entrega (Interactivo)")),
        body: destino == null
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Expanded(
                    child: FlutterMap(
                      options: MapOptions(
                        initialCenter: destino!,
                        initialZoom: 16.0,
                        interactionOptions: const InteractionOptions(
                          // La corrección del error enableScrollWheel:
                          flags: InteractiveFlag.all,
                        )
                      ),
                      children: [
                        TileLayer(
                          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.paquexpress.app',
                        ),
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: destino!,
                              width: 80,
                              height: 80,
                              child: const Icon(Icons.location_pin, color: Colors.red, size: 40),
                            ),
                            if (miPos != null)
                              Marker(
                                point: LatLng(miPos!.latitude, miPos!.longitude),
                                width: 80,
                                height: 80,
                                child: const Icon(Icons.person_pin_circle, color: Colors.blue, size: 40),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Expanded(child: Text("Destino: $direccion")),
                        ElevatedButton(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => ConfirmarEntregaPage(paqueteId: widget.paqueteId)),
                          ),
                          child: const Text("Confirmar aquí"),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      );
}

// -----------------------------------------------------------------
// PÁGINA DE CONFIRMACIÓN
// -----------------------------------------------------------------

class ConfirmarEntregaPage extends StatefulWidget {
  final int paqueteId;
  const ConfirmarEntregaPage({super.key, required this.paqueteId});
  @override
  State<ConfirmarEntregaPage> createState() => _ConfirmarEntregaPageState();
}

class _ConfirmarEntregaPageState extends State<ConfirmarEntregaPage> {
  XFile? photoXFile; 
  Uint8List? photoBytes; // Usado para mostrar la imagen en Web/Desktop
  Position? pos;
  String? fotoUrlPublica; 

  Future<void> _tomarFoto() async {
    // La calidad de imagen se reduce para facilitar la subida
    final img = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 80); 
    if (img != null) {
      photoXFile = img; 
      photoBytes = await img.readAsBytes(); // Lee los bytes para mostrar la vista previa
      setState(() {});
    }
  }

  Future<void> _obtenerGPS() async {
    try {
      await Geolocator.requestPermission();
      pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      setState(() {});
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error al obtener GPS: $e")));
    }
  }

  Future<void> _confirmar() async {
    if (photoXFile == null || pos == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Captura foto y ubicación primero")));
      return;
    }
    try {
      // 1. Subir la foto a FastAPI
      final form = FormData.fromMap({
        'file': MultipartFile.fromBytes(
            await photoXFile!.readAsBytes(), 
            filename: photoXFile!.name,
          ),
      });
      final up = await api.dio.post("/fotos/", data: form);
      fotoUrlPublica = up.data['ruta'];

      // 2. Enviar la confirmación de la entrega
      await api.dio.post("/entregas/confirmar", data: {
        "paquete_id": widget.paqueteId,
        "gps_lat": pos!.latitude,
        "gps_lon": pos!.longitude,
        "foto_url": fotoUrlPublica!,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Entrega confirmada con éxito")));
        // Vuelve a la pantalla principal (Lista de paquetes o Login)
        Navigator.popUntil(context, (route) => route.isFirst); 
      }
    } on DioException catch (e) {
      String msg = e.response?.data.toString() ?? e.message ?? "Error de red desconocido";
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error al confirmar: $msg")));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error inesperado: $e")));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text("Confirmar entrega")),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(child: ElevatedButton.icon(onPressed: _tomarFoto, icon: const Icon(Icons.camera_alt), label: const Text("Foto"))),
                  const SizedBox(width: 12),
                  Expanded(child: ElevatedButton.icon(onPressed: _obtenerGPS, icon: const Icon(Icons.my_location), label: const Text("Ubicación"))),
                ],
              ),
              const SizedBox(height: 16),
              // Muestra la imagen usando bytes (compatible con Web/Desktop)
              if (photoBytes != null)
                Image.memory(photoBytes!, height: 180, width: double.infinity, fit: BoxFit.contain)
              else
                Container(height: 180, alignment: Alignment.center, decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300)), child: const Text("Sin foto")),
              const SizedBox(height: 12),
              Text(pos != null
                  ? "Ubicación: Lat: ${pos!.latitude.toStringAsFixed(6)} · Lon: ${pos!.longitude.toStringAsFixed(6)}"
                  : "Ubicación no obtenida"),
              const Spacer(),
              SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _confirmar, child: const Text("Paquete entregado"))),
            ],
          ),
        ),
      );
}