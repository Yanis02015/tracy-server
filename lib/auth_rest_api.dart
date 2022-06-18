import 'dart:convert';
import 'dart:io';

import 'package:dbcrypt/dbcrypt.dart';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:dotenv/dotenv.dart';
import 'package:jaguar_jwt/jaguar_jwt.dart';
import 'package:tracy_server/auth_middleware.dart';
import 'dart:math';

import 'package:tracy_server/mailer.dart';

class ContactsRestApi {
  var env = DotEnv(includePlatformEnvironment: true)..load();
  ContactsRestApi(this.store);

  DbCollection store;

  Handler get router {
    final app = Router();

    app.get('/', (Request req) async {
      final contacts = await store.find().toList();
      print(contacts);

      return Response.ok(
        json.encode({'employes': contacts}),
        headers: {
          'Content-Type': ContentType.json.mimeType,
        },
      );
    });
    Future<Response> _test(Request req) async {
      print("object");
      final payload = await req.readAsString();

      final data = json.decode(payload);
      print(data);
      return Response.notFound(
        json.encode({'message': 'Utilisateur introuvable'}),
        headers: {
          'Content-Type': ContentType.json.mimeType,
        },
      );
    }

    app.post('/test', Pipeline().addMiddleware(authorize()).addHandler(_test));

    app.post('/login', (Request req) async {
      final payload = await req.readAsString();

      final data = json.decode(payload);

      final user = await store.findOne({'email': data['email']});
      if (user == null) {
        return Response.notFound(
          json.encode({'message': 'Utilisateur introuvable'}),
          headers: {
            'Content-Type': ContentType.json.mimeType,
          },
        );
      }
      var isCorrect = DBCrypt().checkpw(data['password'], user['password']);
      if (!isCorrect) {
        return Response.notFound(
          json.encode({'message': 'Mot de passe incorrect'}),
          headers: {
            'Content-Type': ContentType.json.mimeType,
          },
        );
      }
      final claimSet = JwtClaim(
          issuer: 'Dart Server',
          subject: '${user['_id']}',
          issuedAt: DateTime.now(),
          maxAge: const Duration(hours: 120));

      String token = issueJwtHS256(claimSet, env['JWT_AUTH_SECRET']!);
      final message = user['status'] == 1
          ? 'Connecté avec succès'
          : 'Connecté avec succès mais confirmation de l\'email est demandé';
      final statusCode =
          user['status'] == 1 ? HttpStatus.ok : HttpStatus.forbidden;
      return Response(
        statusCode,
        body: json.encode({
          'user': user,
          'message': message,
          'status': '${user['status']}',
          'token': '${objectIdToString(user['_id'].toString())} $token'
        }),
        headers: {
          'Content-Type': ContentType.json.mimeType,
        },
      );
    });

    app.post('/register', (Request req) async {
      final payload = await req.readAsString();
      final data = json.decode(payload);
      data["status"] = 0; // Email non confirmé
      data['password'] =
          DBCrypt().hashpw(data['password'], DBCrypt().gensalt());
      final isEmailExist =
          (await store.findOne(where.eq('email', data['email']))) != null;
      print(isEmailExist);
      if (isEmailExist) {
        return Response(
          HttpStatus.conflict,
          body: json.encode({'message': 'Email déjà utilisé'}),
          headers: {
            'Content-Type': ContentType.json.mimeType,
          },
        );
      }
      final code = await sendEmail(data!['email'], 1);
      if (code > 100000) {
        data['codeConfirmeEmail'] = code;
        await store.insert(data);
        final addedEntry =
            await store.findOne(where.eq('email', data['email']));
        return Response(
          HttpStatus.created,
          body: json.encode(addedEntry),
          headers: {
            'Content-Type': ContentType.json.mimeType,
          },
        );
      }
      return Response.internalServerError(
        headers: {
          'Content-Type': ContentType.json.mimeType,
        },
      );
    });

    app.post('/send-code', (Request req) async {
      final payload = await req.readAsString();
      final data = json.decode(payload);
      final user = await store.findOne(where.eq('email', data['email']));
      final code = await sendEmail(user!['email'], 1);
      if (code > 100000) {
        user['codeConfirmeEmail'] = code;
        await store.replaceOne({'email': user['email']}, user);
        return Response.ok(
          json.encode({'message': 'Code envoyé'}),
          headers: {
            'Content-Type': ContentType.json.mimeType,
          },
        );
      }
      return Response.internalServerError(
        headers: {
          'Content-Type': ContentType.json.mimeType,
        },
      );
    });

    app.post('/confirme-code', (Request req) async {
      final payload = await req.readAsString();
      final data = json.decode(payload);
      final user = await store.findOne(where.eq('email', data['email']));
      if (user == null) {
        return Response.notFound(
          json.encode({'message': 'Utilisateur introuvable'}),
          headers: {
            'Content-Type': ContentType.json.mimeType,
          },
        );
      }
      if (data['code'] == user['codeConfirmeEmail'].toString()) {
        user['status'] = 1; // email confirmé
        await store.replaceOne({'email': user['email']}, user);
        print('c ok');
        return Response.ok(
          json.encode({'message': 'Email confirmé avec sucée'}),
          headers: {
            'Content-Type': ContentType.json.mimeType,
          },
        );
      }
      return Response.notFound(
        json.encode({'message': 'Code invalide'}),
        headers: {
          'Content-Type': ContentType.json.mimeType,
        },
      );
    });

    app.post('/send-email-code-forget-password', (Request req) async {
      final payload = await req.readAsString();
      final data = json.decode(payload);
      final user = await store.findOne(where.eq('email', data['email']));
      if (user == null) {
        return Response.notFound(
          json.encode({'message': 'Utilisateur introuvable'}),
          headers: {
            'Content-Type': ContentType.json.mimeType,
          },
        );
      }
      final code = await sendEmail(user['email'], 0);
      if (code > 100000) {
        user['codeConfirmeRestPassword'] = code;
        await store.replaceOne({'email': user['email']}, user);
        return Response.ok(
          json.encode({'message': 'Code envoyé'}),
          headers: {
            'Content-Type': ContentType.json.mimeType,
          },
        );
      }
      return Response.internalServerError(
        headers: {
          'Content-Type': ContentType.json.mimeType,
        },
      );
    });

    app.post("/confirme-code-reset-password", (Request req) async {
      final payload = await req.readAsString();
      final data = json.decode(payload);
      final user = await store.findOne(where.eq('email', data['email']));
      if (user == null) {
        return Response.notFound(
          json.encode({'message': 'Utilisateur introuvable'}),
          headers: {
            'Content-Type': ContentType.json.mimeType,
          },
        );
      }
      if (data['code'] == user['codeConfirmeRestPassword'].toString()) {
        return Response.ok(
          json.encode({'message': 'Code correct'}),
          headers: {
            'Content-Type': ContentType.json.mimeType,
          },
        );
      }
      return Response.notFound(
        json.encode({'message': 'Code invalide'}),
        headers: {
          'Content-Type': ContentType.json.mimeType,
        },
      );
    });

    app.post('/reset-forget-password', (Request req) async {
      final payload = await req.readAsString();
      final data = json.decode(payload);
      final user = await store.findOne(where.eq('email', data['email']));
      if (user == null) {
        return Response.notFound(
          json.encode({'message': 'Utilisateur introuvable'}),
          headers: {
            'Content-Type': ContentType.json.mimeType,
          },
        );
      }
      if (data['code'] == user['codeConfirmeRestPassword'].toString()) {
        user['password'] = DBCrypt()
            .hashpw(data['password'], DBCrypt().gensalt()); // new password
        await store.replaceOne({'email': user['email']}, user);
        return Response.ok(
          json.encode({'message': 'Mot de passe changer avec succès'}),
          headers: {
            'Content-Type': ContentType.json.mimeType,
          },
        );
      }
      return Response.notFound(
        json.encode({'message': 'Code invalide'}),
        headers: {
          'Content-Type': ContentType.json.mimeType,
        },
      );
    });

    app.delete('/<id|.+>', (Request req, String id) async {
      // final JwtClaim decClaimSet =
      //     verifyJwtHS256Signature(token, env['JWT_AUTH_SECRET']!);
      // print(decClaimSet.subject!.toString() == user['_id'].toString());
      await store.deleteOne(where.eq('_id', ObjectId.fromHexString(id)));
      return Response.ok('Deleted $id');
    });

    return app;
  }

  Future<int> sendEmail(email, emailCase) async {
    const min = 100000;
    const max = 1000000; // Maximum is 999999
    final int code = Random().nextInt(max - min) +
        min; // Maximum is 999999 ; Minimum is 100000
    final emailRes = await tracyMail(email, code, emailCase);
    return emailRes ? code : 0;
  }

  objectIdToString(String userId) {
    return userId.split('"')[1];
  }
}
