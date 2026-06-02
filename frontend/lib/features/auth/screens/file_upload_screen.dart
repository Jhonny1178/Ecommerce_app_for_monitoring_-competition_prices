import 'package:flutter/material.dart';
import 'package:tonten/core/api/api_client.dart';
import 'package:http/http.dart' as http;
import 'auth_router.dart';
import 'dart:convert';
import 'login_screen.dart';
import 'package:file_picker/file_picker.dart';

class FileUploadScreen extends StatefulWidget {
  const FileUploadScreen({super.key});

  @override
  State<FileUploadScreen> createState() => _FileUploadScreenState();
}

class _FileUploadScreenState extends State<FileUploadScreen> {
  bool _isLoading = false;

  final _messageController = TextEditingController();
  bool _isSendingMessage = false;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _pickAndUploadFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'xlsx', 'xls', 'json', 'xml'],
      withData: true,
    );

    if (result == null || result.files.isEmpty) {
      return; // User canceled
    }

    final fileBytes = result.files.first.bytes;
    final fileName = result.files.first.name;

    if (fileBytes == null) {
       if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Błąd odczytu pliku.'), backgroundColor: Colors.red),
          );
       }
       return;
    }

    setState(() => _isLoading = true);
    try {
      final url = Uri.parse("/api/upload_onboarding_file");
      
      var request = http.MultipartRequest('POST', url);
      request.files.add(http.MultipartFile.fromBytes(
        'file',
        fileBytes,
        filename: fileName,
      ));
      
      final response = await request.send();
      final respData = await response.stream.bytesToString();
      final data = jsonDecode(respData);

      if (response.statusCode == 200 && data['ok'] == true) {
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const AuthRouter(status: 'pending_approval', isAdmin: false)),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(data['error'] ?? 'Wystąpił błąd'), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Błąd połączenia: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;
    
    setState(() => _isSendingMessage = true);
    try {
      final url = Uri.parse("/api/send_message");
      final response = await ApiClient.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'message': _messageController.text.trim()}),
      );
      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['ok'] == true) {
        if (mounted) {
          _messageController.clear();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Wiadomość wysłana pomyślnie.'), backgroundColor: Colors.green),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(data['error'] ?? 'Wystąpił błąd'), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Błąd połączenia: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSendingMessage = false);
    }
  }

  void _logout() async {
    await ApiClient.post(Uri.parse("/api/logout"));
    if (mounted) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('Krok 1: Wgranie cennika'),
        actions: [
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout)
        ],
      ),
      body: Center(
        child: Container(
          width: 600,
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.upload_file, size: 64, color: colorScheme.primary),
              const SizedBox(height: 24),
              const Text(
                'Wgraj plik z produktami',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Text(
                'Prosimy o wgranie pliku w formacie CSV z kluczowymi informacjami: nazwa, cena, kategoria, ean/sku.\n\nSzanujemy Twoją prywatność, przestrzegamy prawa, a Twoje dane są wykorzystywane wyłącznie do analizy możliwości naszej współpracy.',
                textAlign: TextAlign.center,
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              Text(
                'W razie problemów napisz: kontakt@e-roch.pl',
                style: TextStyle(color: colorScheme.primary, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: _isLoading ? null : _pickAndUploadFile,
                icon: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Icon(Icons.file_upload),
                label: const Text('Wybierz plik i prześlij'),
                style: FilledButton.styleFrom(padding: const EdgeInsets.all(24)),
              ),
              const SizedBox(height: 32),
              const Divider(),
              const SizedBox(height: 16),
              const Text(
                'Masz pytania do wyceny / wdrożenia?',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _messageController,
                maxLines: 4,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: colorScheme.surface,
                  hintText: 'Napisz swoją wiadomość tutaj...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: _isSendingMessage ? null : _sendMessage,
                  icon: _isSendingMessage ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.send),
                  label: const Text('Wyślij wiadomość'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
