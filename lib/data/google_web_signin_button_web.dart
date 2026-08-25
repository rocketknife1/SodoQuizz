import 'package:flutter/widgets.dart';
import 'package:google_sign_in_web/web_only.dart' as web_gsi;

/// Butonul chiar randat de Google (GIS) în DOM — vezi
/// google_web_signin_button.dart pentru de ce e obligatoriu pe web.
/// SizedBox cu lățime fixă (nu double.infinity — GSI cere un `minimumWidth`
/// concret în pixeli, altfel randează la lățimea lui minimă implicită).
Widget buildGoogleWebSignInButton() {
  return SizedBox(
    width: 320,
    height: 44,
    child: web_gsi.renderButton(
      configuration: web_gsi.GSIButtonConfiguration(
        theme: web_gsi.GSIButtonTheme.filledBlue,
        size: web_gsi.GSIButtonSize.large,
        text: web_gsi.GSIButtonText.signinWith,
        shape: web_gsi.GSIButtonShape.pill,
        minimumWidth: 320,
      ),
    ),
  );
}
