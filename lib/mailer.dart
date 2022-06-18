import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';

Future<bool> tracyMail(String email, int code, int emailCase) async {
  print('object');
  String username = 'saeel.electromenager@gmail.com';
  String name = 'Tracy';
  String password = 'wndordsfuxzjakfx';

  final smtpServer = gmail(username, password);
  // Use the SmtpServer class to configure an SMTP server:
  // final smtpServer = SmtpServer('smtp.domain.com');
  // See the named arguments of SmtpServer for further configuration
  // options.

  // Create our message.
  Message message = Message()
    ..from = Address(username, name)
    ..recipients.add(email)
    ..subject = 'Confirmation de votre email Tracy'
    ..html =
        '<h1>Code de confirmation d\'email</h1>\n<p>Votre code est : </p><br/><h1>$code</h1><p>Tracy vous remercie pour votre confiance</p>';
  if (emailCase == 0) {
    message = Message()
      ..from = Address(username, name)
      ..recipients.add(email)
      ..subject = 'Récupération de votre compte Tracy'
      ..html =
          '<h1>Code de récupération de compte</h1>\n<p>Votre code est : </p><br/><h1>$code</h1><p>Tracy vous remercie pour votre confiance</p>';
  }
  try {
    final sendReport = await send(message, smtpServer);
    print('Message sent: ' + sendReport.toString());
    return true;
  } on MailerException catch (e) {
    print('Message not sent.');
    for (var p in e.problems) {
      print('Problem: ${p.code}: ${p.msg}');
    }
    return false;
  }
  // DONE
}
