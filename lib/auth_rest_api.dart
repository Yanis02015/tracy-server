import 'dart:convert';
import 'dart:io';

import 'package:dbcrypt/dbcrypt.dart';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:dotenv/dotenv.dart';
import 'package:jaguar_jwt/jaguar_jwt.dart';

class ContactsRestApi {
  var env = DotEnv(includePlatformEnvironment: true)..load();
  ContactsRestApi(this.store);

  DbCollection store;

  Handler get router {
    final app = Router();

    app.get('/', (Request req) async {
      final contacts = await store.find().toList();
      return Response.ok(
        json.encode({'employes': contacts}),
        headers: {
          'Content-Type': ContentType.json.mimeType,
        },
      );
    });

    app.post('/login', (Request req) async {
      final payload = await req.readAsString();

      final data = json.decode(payload);
      final user = await store.findOne({'email': data['email']});
      if (user == null) {
        return Response.notFound(
          json.encode({'error': 'Utilisateur introuvable'}),
          headers: {
            'Content-Type': ContentType.json.mimeType,
          },
        );
      }
      var isCorrect = DBCrypt().checkpw(data['password'], user['password']);
      if (!isCorrect) {
        return Response.notFound(
          json.encode({'error': 'Mot de passe incorrect'}),
          headers: {
            'Content-Type': ContentType.json.mimeType,
          },
        );
      }
      final claimSet = JwtClaim(
          issuer: 'Dart Server',
          subject: '${user['_id']}',
          issuedAt: DateTime.now(),
          maxAge: const Duration(hours: 12));

      String token = issueJwtHS256(claimSet, env['JWT_AUTH_SECRET']!);
      return Response.ok(
        json.encode(
            {'user': user, 'message': 'Connecté avec succès', token: token}),
        headers: {
          'Content-Type': ContentType.json.mimeType,
        },
      );
    });

    app.post('/register', (Request req) async {
      final payload = await req.readAsString();
      final data = json.decode(payload);
      data['password'] =
          DBCrypt().hashpw(data['password'], DBCrypt().gensalt());
      await store.insert(data);
      final addedEntry = await store.findOne(where.eq('email', data['email']));

      return Response(
        HttpStatus.created,
        body: json.encode(addedEntry),
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
}
