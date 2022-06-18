import 'package:jaguar_jwt/jaguar_jwt.dart';
import 'package:shelf/shelf.dart';
import 'package:dotenv/dotenv.dart';

Middleware authorize() => (innerHandler) {
      var env = DotEnv(includePlatformEnvironment: true)..load();
      return (request) async {
        final authorizationHeader = request.headers['Authorization'] ??
            request.headers['authorization'];

        if (authorizationHeader == null) {
          return Response(401);
        }

        final userId = authorizationHeader.split(" ")[0];
        final token = authorizationHeader.split(" ")[1];

        if (token.isEmpty) {
          return Response(401);
        }

        final JwtClaim jwtClaim =
            verifyJwtHS256Signature(token, env['JWT_AUTH_SECRET']!);

        if (jwtClaim.subject != userId) {
          print(jwtClaim.subject);
          print(token);
          return Response(401);
        }
        return Future.sync(() => innerHandler(request)).then((response) {
          return response;
        });
      };
    };
