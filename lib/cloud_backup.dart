import 'dart:typed_data';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'backup.dart';
import 'store.dart';

class GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _client = http.Client();

  GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _client.send(request);
  }

  @override
  void close() {
    _client.close();
    super.close();
  }
}

class CloudBackupService {
  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [drive.DriveApi.driveAppdataScope],
  );

  static GoogleSignInAccount? get currentUser => _googleSignIn.currentUser;

  static Future<GoogleSignInAccount?> signIn() async {
    return await _googleSignIn.signIn();
  }

  static Future<void> signOut() async {
    await _googleSignIn.signOut();
  }

  static Future<drive.DriveApi?> _getDriveApi() async {
    final account = _googleSignIn.currentUser ?? await _googleSignIn.signInSilently();
    if (account == null) return null;
    final auth = await account.authentication;
    final token = auth.accessToken;
    if (token == null) return null;

    final client = GoogleAuthClient({'Authorization': 'Bearer $token'});
    return drive.DriveApi(client);
  }

  static const String backupFileName = 'maaser_cloud_backup.maaserbackup';

  /// העלאת גיבוי ל-Google Drive (App Data Folder)
  static Future<bool> uploadBackup(Store s) async {
    final driveApi = await _getDriveApi();
    if (driveApi == null) return false;

    final bytes = await createBackup(s);
    
    // חיפוש האם קיים כבר קובץ גיבוי בענן
    final list = await driveApi.files.list(
      spaces: 'appDataFolder',
      q: "name = '$backupFileName'",
    );

    final media = drive.Media(Stream.value(bytes), bytes.length);
    final driveFile = drive.File()
      ..name = backupFileName
      ..parents = ['appDataFolder'];

    if (list.files != null && list.files!.isNotEmpty) {
      final fileId = list.files!.first.id!;
      await driveApi.files.update(driveFile, fileId, uploadMedia: media);
    } else {
      await driveApi.files.create(driveFile, uploadMedia: media);
    }
    return true;
  }

  /// הורדה ושחזור גיבוי מ-Google Drive (App Data Folder)
  static Future<bool> downloadAndRestoreBackup(Store s) async {
    final driveApi = await _getDriveApi();
    if (driveApi == null) return false;

    final list = await driveApi.files.list(
      spaces: 'appDataFolder',
      q: "name = '$backupFileName'",
    );

    if (list.files == null || list.files!.isEmpty) {
      throw Exception('לא נמצא גיבוי קודם בענן.');
    }

    final fileId = list.files!.first.id!;
    final drive.Media media = await driveApi.files.get(
      fileId,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;

    final dataBytes = await media.stream.fold<List<int>>(<int>[], (buffer, chunk) => buffer..addAll(chunk));
    final uint8Bytes = Uint8List.fromList(dataBytes);

    await restoreBackup(s, uint8Bytes);
    return true;
  }
}
