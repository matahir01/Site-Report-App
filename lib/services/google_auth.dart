import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:http/http.dart' as http;

/// Single shared [GoogleSignIn] instance for the whole app. Both the Drive
/// backup feature and the Google Sheets sync feature request their scopes
/// together up front, so the user only ever sees one consent screen instead
/// of being asked to grant access twice.
class GoogleAuth {
  static final GoogleSignIn instance = GoogleSignIn(
    scopes: [
      drive.DriveApi.driveAppdataScope,
      sheets.SheetsApi.spreadsheetsScope,
      // Lets the app create/open spreadsheet files it created in the
      // user's normal (visible) Drive — separate from the hidden
      // appDataFolder space used for database backups.
      drive.DriveApi.driveFileScope,
    ],
  );

  /// Signs in only if a session already exists — never shows the account
  /// picker. Used for background/auto-sync so routine saves don't
  /// interrupt the user with a sign-in prompt.
  static Future<GoogleSignInAccount?> signInSilentlyOnly() {
    return instance.signInSilently();
  }

  /// Signs in interactively if needed — shows the account picker. Used
  /// only for explicit user actions like "Connect & Sync".
  static Future<GoogleSignInAccount?> signInInteractive() async {
    return await instance.signInSilently() ?? await instance.signIn();
  }

  static Future<http.Client> _authedClient(GoogleSignInAccount account) async {
    final auth = await account.authentication;
    if (auth.accessToken == null) {
      throw Exception('Google Sign-In failed: no access token');
    }
    return _AuthClient(http.Client(), auth.accessToken!);
  }

  static Future<drive.DriveApi> driveApiFor(GoogleSignInAccount account) async {
    return drive.DriveApi(await _authedClient(account));
  }

  static Future<sheets.SheetsApi> sheetsApiFor(
    GoogleSignInAccount account,
  ) async {
    return sheets.SheetsApi(await _authedClient(account));
  }
}

class _AuthClient extends http.BaseClient {
  final http.Client _inner;
  final String _accessToken;

  _AuthClient(this._inner, this._accessToken);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Authorization'] = 'Bearer $_accessToken';
    return _inner.send(request);
  }
}
