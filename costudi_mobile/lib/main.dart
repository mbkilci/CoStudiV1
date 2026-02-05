import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:universal_html/html.dart' as html;
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:path/path.dart' as p;

void main() {
  runApp(const CostudiApp());
}

class CostudiApp extends StatelessWidget {
  const CostudiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CoStudi',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.grey.shade50,
        fontFamily: 'Roboto',
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final String baseUrl = "http://127.0.0.1:8000"; 
  
  List<PlatformFile>? _files;
  bool _isLoading = false;
  bool _isHovering = false; // Hover durumu için
  String _targetFormat = "PNG";

  // --- DOSYA SEÇME ---
  Future<void> _pickFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true, 
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'png', 'jpeg', 'docx', 'pptx'],
        withData: true, 
      );

      if (result != null) {
        setState(() { _files = result.files; });
      }
    } catch (e) {
      print("Hata: $e");
    }
  }

  void _clearSelection() {
    setState(() { _files = null; });
  }

  // --- NAVİGASYON ---
  void _navigateToMergeEditor() {
    if (_files == null) return;
    Navigator.push(context, MaterialPageRoute(builder: (context) => MergeEditorScreen(initialFiles: _files!, baseUrl: baseUrl)));
  }

  void _navigateToSplitScreen() {
    if (_files == null) return;
    if (_files!.first.bytes != null) {
      Navigator.push(context, MaterialPageRoute(builder: (context) => PdfVisualSplitScreen(fileBytes: _files!.first.bytes!, fileName: _files!.first.name, baseUrl: baseUrl)));
    }
  }

  // --- İŞLEMLER ---
  Future<void> _processImage() async {
    if (_files == null) return;
    setState(() => _isLoading = true);
    String opTag = "img2$_targetFormat".toLowerCase();
    await _sendRequestSimple(
      endpoint: "image-process", 
      fields: {'format': _targetFormat.toLowerCase(), 'quality': '100'},
      forcedExtension: _targetFormat.toLowerCase(),
      operationTag: opTag
    );
    setState(() => _isLoading = false);
  }

  Future<void> _pdfToDocx() async {
    if (_files == null) return;
    setState(() => _isLoading = true);
    await _sendRequestSimple(
      endpoint: "pdf-to-docx", 
      forcedExtension: "docx",
      operationTag: "pdf2docx"
    );
    setState(() => _isLoading = false);
  }

  Future<void> _officeToPdf() async {
    if (_files == null) return;
    setState(() => _isLoading = true);
    String originalExt = _files!.first.extension ?? "office";
    String opTag = "${originalExt}2pdf";
    await _sendRequestSimple(
      endpoint: "office-to-pdf", 
      forcedExtension: "pdf",
      operationTag: opTag
    );
    setState(() => _isLoading = false);
  }

  Future<void> _sendRequestSimple({
    required String endpoint, 
    Map<String, String>? fields, 
    String? forcedExtension,
    required String operationTag
  }) async {
    try {
      var request = http.MultipartRequest('POST', Uri.parse("$baseUrl/$endpoint/"));
      request.files.add(http.MultipartFile.fromBytes('file', _files!.first.bytes!, filename: _files!.first.name));
      if (fields != null) request.fields.addAll(fields);

      var response = await request.send();
      if (response.statusCode == 200) {
        final bytes = await response.stream.toBytes();
        String ext = forcedExtension ?? _targetFormat.toLowerCase();
        String defaultName = p.basenameWithoutExtension(_files!.first.name);

        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => FilenameDialog(
              fileBytes: bytes,
              extension: ext,
              defaultName: defaultName,
              operationTag: operationTag,
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Sunucu Hatası: ${response.statusCode}"), backgroundColor: Colors.red));
      }
    } catch (e) {
      print(e);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Hata: $e"), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isFileSelected = _files != null;
    bool isMultiple = isFileSelected && _files!.length > 1;
    
    String? ext = isFileSelected ? _files!.first.extension : null;
    bool isPdf = ext == 'pdf';
    bool isOffice = ext == 'docx' || ext == 'pptx';
    bool isImage = ext == 'jpg' || ext == 'png' || ext == 'jpeg';

    return Scaffold(
      appBar: AppBar(
        // GÜNCELLENDİ: Sadece CoStudi yazıyor, font kalınlaştırıldı
        title: const Text(
          "CoStudi", 
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.0)
        ), 
        centerTitle: true
      ),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600),
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (!isFileSelected)
                // GÜNCELLENDİ: MouseRegion ve AnimatedContainer ile Hover Efekti
                MouseRegion(
                  onEnter: (_) => setState(() => _isHovering = true),
                  onExit: (_) => setState(() => _isHovering = false),
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: _pickFiles,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200), // Yumuşak geçiş
                      height: 250, 
                      width: double.infinity,
                      decoration: BoxDecoration(
                        // Hover olunca renk ve kenarlık değişiyor
                        color: _isHovering ? Colors.indigo.shade50 : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _isHovering ? Colors.indigo : Colors.indigo.shade100, 
                          width: _isHovering ? 2.5 : 2
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.indigo.withOpacity(_isHovering ? 0.1 : 0.05), 
                            blurRadius: 20
                          )
                        ],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.cloud_upload_rounded, 
                            size: 80, 
                            color: _isHovering ? Colors.indigo : Colors.indigo.shade300
                          ),
                          const SizedBox(height: 20),
                          Text(
                            "Dosya Seç veya Sürükle", 
                            style: TextStyle(
                              fontSize: 20, 
                              fontWeight: FontWeight.bold, 
                              color: _isHovering ? Colors.indigo : Colors.indigo.shade700
                            )
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            "PDF • DOCX • PPTX • JPG • PNG", 
                            style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              if (isFileSelected) ...[
                Card(
                  elevation: 5, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  child: ListTile(
                    leading: Icon(
                      isPdf ? Icons.picture_as_pdf : (isOffice ? Icons.description : Icons.image), 
                      size: 40, 
                      color: isPdf ? Colors.red : (isOffice ? Colors.blue.shade800 : Colors.purple)
                    ),
                    title: Text(isMultiple ? "${_files!.length} Dosya Seçildi" : _files!.first.name),
                    subtitle: Text(isMultiple ? "Toplu İşlem" : "${(_files!.first.size / 1024).toStringAsFixed(1)} KB"),
                    trailing: IconButton(onPressed: _clearSelection, icon: const Icon(Icons.close, color: Colors.red)),
                  ),
                ),
                const SizedBox(height: 30),

                if (isMultiple) ...[
                  _buildBigButton(icon: Icons.merge_type, title: "Sıralama Editörü & Birleştir", subtitle: "Seçilenleri tek PDF yap", color: Colors.orange, onTap: _navigateToMergeEditor),
                ]
                else if (isOffice) ...[
                   _buildBigButton(icon: Icons.picture_as_pdf, title: "PDF'e Dönüştür", subtitle: "Dosyayı PDF formatına çevir", color: Colors.red, onTap: _officeToPdf),
                ]
                else if (isPdf) ...[
                  Row(
                    children: [
                      Expanded(child: _buildBigButton(icon: Icons.grid_view_rounded, title: "Sayfaları Ayır", color: Colors.indigo, onTap: _navigateToSplitScreen)),
                      const SizedBox(width: 10),
                      Expanded(child: _buildBigButton(icon: Icons.article, title: "Word'e Çevir", color: Colors.blue.shade800, onTap: _pdfToDocx)),
                    ],
                  )
                ]
                else if (isImage) ...[
                   DropdownButton<String>(
                    value: _targetFormat,
                    items: ["PNG", "JPG", "PDF", "WEBP"].map((e) => DropdownMenuItem(value: e, child: Text("Hedef: $e"))).toList(),
                    onChanged: (v) => setState(() => _targetFormat = v!),
                  ),
                  const SizedBox(height: 10),
                  _buildBigButton(icon: Icons.transform, title: "Dönüştür ve İndir", color: Colors.green, onTap: _processImage),
                ]
              ],

              if (_isLoading) const Padding(padding: EdgeInsets.only(top: 20), child: CircularProgressIndicator())
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBigButton({required IconData icon, required String title, String? subtitle, required Color color, required VoidCallback onTap}) {
    return SizedBox(
      height: subtitle != null ? 70 : 50,
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isLoading ? null : onTap,
        style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 24),
                const SizedBox(width: 10),
                Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            if (subtitle != null) Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
      ),
    );
  }
}

// --- DİYALOG VE DİĞER EKRANLAR AYNI KALIYOR ---

class FilenameDialog extends StatefulWidget {
  final List<int> fileBytes;
  final String extension;
  final String? defaultName; 
  final String operationTag; 

  const FilenameDialog({super.key, required this.fileBytes, required this.extension, this.defaultName, required this.operationTag});

  @override
  State<FilenameDialog> createState() => _FilenameDialogState();
}

class _FilenameDialogState extends State<FilenameDialog> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.defaultName ?? "");
  }

  void _download() {
    String userInput = _controller.text.trim();
    String finalName;
    if (userInput.isEmpty) {
      finalName = "CoStudi_${widget.operationTag}.${widget.extension}";
    } else {
      finalName = "$userInput(CoStudi_${widget.operationTag}).${widget.extension}";
    }
    final blob = html.Blob([widget.fileBytes]);
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)..setAttribute("download", finalName)..click();
    html.Url.revokeObjectUrl(url);
    Navigator.pop(context); 
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Dosya İndiriliyor: $finalName"), backgroundColor: Colors.green));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Dosya İsmini Belirle"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("İndirmeden önce dosyanıza bir isim verin:"),
          const SizedBox(height: 15),
          Row(
            children: [
              Expanded(child: TextField(controller: _controller, autofocus: true, decoration: const InputDecoration(hintText: "Dosya adı...", border: OutlineInputBorder(), isDense: true))),
              const SizedBox(width: 8),
              Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12), decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.grey.shade400)), child: Text(".${widget.extension}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black54))),
            ],
          ),
          const SizedBox(height: 10),
          Text("İmza: (CoStudi_${widget.operationTag}) otomatik eklenecektir.", style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontStyle: FontStyle.italic))
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("İptal")),
        ElevatedButton(onPressed: _download, style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white), child: const Text("İndir")),
      ],
    );
  }
}

class MergeEditorScreen extends StatefulWidget {
  final List<PlatformFile> initialFiles;
  final String baseUrl;
  const MergeEditorScreen({super.key, required this.initialFiles, required this.baseUrl});
  @override
  State<MergeEditorScreen> createState() => _MergeEditorScreenState();
}

class _MergeEditorScreenState extends State<MergeEditorScreen> {
  late List<PlatformFile> _files;
  bool _isLoading = false;
  @override
  void initState() {
    super.initState();
    _files = List.from(widget.initialFiles);
  }
  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (oldIndex < newIndex) newIndex -= 1;
      final PlatformFile item = _files.removeAt(oldIndex);
      _files.insert(newIndex, item);
    });
  }
  void _removeFile(int index) {
    setState(() { _files.removeAt(index); });
  }
  Future<void> _mergeAndDownload() async {
    if (_files.isEmpty) return;
    setState(() => _isLoading = true);
    try {
      var request = http.MultipartRequest('POST', Uri.parse("${widget.baseUrl}/pdf-merge/"));
      for (var file in _files) {
        request.files.add(http.MultipartFile.fromBytes('files', file.bytes!, filename: file.name));
      }
      var response = await request.send();
      if (response.statusCode == 200) {
        final bytes = await response.stream.toBytes();
        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => FilenameDialog(
              fileBytes: bytes, extension: "pdf", defaultName: null, operationTag: "merge",
            ),
          );
        }
      } else { throw Exception("Sunucu hatası: ${response.statusCode}"); }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Hata: $e"), backgroundColor: Colors.red));
    } finally { setState(() => _isLoading = false); }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Dosyaları Sırala"), centerTitle: true),
      body: Column(
        children: [
           Container(padding: const EdgeInsets.all(10), color: Colors.blue.shade50, child: const Row(children: [Icon(Icons.info_outline, color: Colors.blue), SizedBox(width: 10), Expanded(child: Text("Dosyaları basılı tutup sürükleyerek sırasını değiştirin."))])),
           Expanded(child: ReorderableListView(padding: const EdgeInsets.all(10), onReorder: _onReorder, children: [for (int index = 0; index < _files.length; index++) Card(key: ValueKey(_files[index].name + index.toString()), elevation: 2, margin: const EdgeInsets.symmetric(vertical: 5), child: ListTile(leading: Icon(_files[index].extension == 'pdf' ? Icons.picture_as_pdf : Icons.image, color: _files[index].extension == 'pdf' ? Colors.red : Colors.blue), title: Text(_files[index].name), trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.grey), onPressed: () => _removeFile(index))))])),
           Container(padding: const EdgeInsets.all(20), decoration: const BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -5))]), child: ElevatedButton.icon(onPressed: (_files.isEmpty || _isLoading) ? null : _mergeAndDownload, style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 15)), icon: _isLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.merge_type), label: Text("Bu Sırayla Birleştir (${_files.length} Dosya)")))
        ],
      ),
    );
  }
}

class PdfVisualSplitScreen extends StatefulWidget {
  final Uint8List fileBytes;
  final String fileName;
  final String baseUrl;
  const PdfVisualSplitScreen({super.key, required this.fileBytes, required this.fileName, required this.baseUrl});
  @override
  State<PdfVisualSplitScreen> createState() => _PdfVisualSplitScreenState();
}

class _PdfVisualSplitScreenState extends State<PdfVisualSplitScreen> {
  final Set<int> _selectedPages = {}; 
  bool _isLoading = false;
  late Future<List<Uint8List>> _pagesFuture;
  @override
  void initState() {
    super.initState();
    _pagesFuture = _generateThumbnails();
  }
  Future<List<Uint8List>> _generateThumbnails() async {
    List<Uint8List> images = [];
    await for (final page in Printing.raster(widget.fileBytes, dpi: 72)) {
      images.add(await page.toPng());
    }
    return images;
  }
  void _togglePage(int index) {
    setState(() {
      if (_selectedPages.contains(index)) _selectedPages.remove(index);
      else _selectedPages.add(index);
    });
  }
  Future<void> _extractPages() async {
    if (_selectedPages.isEmpty) return;
    setState(() => _isLoading = true);
    try {
      final sortedPages = _selectedPages.toList()..sort();
      final pageString = sortedPages.join(",");
      var request = http.MultipartRequest('POST', Uri.parse("${widget.baseUrl}/pdf-extract/"));
      request.files.add(http.MultipartFile.fromBytes('file', widget.fileBytes, filename: widget.fileName));
      request.fields['selected_pages'] = pageString;
      var response = await request.send();
      if (response.statusCode == 200) {
        final bytes = await response.stream.toBytes();
        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => FilenameDialog(
              fileBytes: bytes, extension: "pdf", defaultName: null, operationTag: "split",
            ),
          );
        }
      } else { throw Exception("Sunucu hatası: ${response.statusCode}"); }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Hata: $e"), backgroundColor: Colors.red));
    } finally { setState(() => _isLoading = false); }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.fileName, style: const TextStyle(fontSize: 14)), actions: [FutureBuilder<List<Uint8List>>(future: _pagesFuture, builder: (context, snapshot) { if (!snapshot.hasData) return const SizedBox(); return IconButton(icon: const Icon(Icons.select_all), onPressed: () { setState(() { if (_selectedPages.length == snapshot.data!.length) _selectedPages.clear(); else for (int i=0; i < snapshot.data!.length; i++) _selectedPages.add(i); }); }); })]),
      body: FutureBuilder<List<Uint8List>>(
        future: _pagesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError) return Center(child: Text("Hata: ${snapshot.error}"));
          final images = snapshot.data!;
          return Column(
            children: [
              Expanded(child: GridView.builder(padding: const EdgeInsets.all(10), gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 0.7, crossAxisSpacing: 10, mainAxisSpacing: 10), itemCount: images.length, itemBuilder: (context, index) { final isSelected = _selectedPages.contains(index); return GestureDetector(onTap: () => _togglePage(index), child: Container(decoration: BoxDecoration(border: isSelected ? Border.all(color: Colors.green, width: 3) : Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)), child: Stack(children: [ClipRRect(borderRadius: BorderRadius.circular(5), child: Image.memory(images[index], fit: BoxFit.cover, width: double.infinity, height: double.infinity)), if (isSelected) Positioned(right: 5, top: 5, child: Container(padding: const EdgeInsets.all(2), decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle), child: const Icon(Icons.check, color: Colors.white, size: 16))), Positioned(bottom: 5, left: 0, right: 0, child: Center(child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)), child: Text("${index + 1}", style: const TextStyle(color: Colors.white, fontSize: 10)))))],),),);})),
              Container(padding: const EdgeInsets.all(20), decoration: const BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -5))]), child: ElevatedButton.icon(onPressed: (_selectedPages.isEmpty || _isLoading) ? null : _extractPages, style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 15)), icon: _isLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.cut), label: Text(_selectedPages.isEmpty ? "Sayfa Seçin" : "${_selectedPages.length} Sayfayı Ayır ve İndir")))
            ],
          );
        },
      ),
    );
  }
}