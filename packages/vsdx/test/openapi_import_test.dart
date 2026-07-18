import 'package:test/test.dart';
import 'package:vsdx/agent.dart';
import 'package:vsdx/vsdx.dart';

const _yaml = '''
openapi: 3.0.0
info:
  title: Pet Store
paths:
  /pets:
    get:
      responses:
        '200':
          content:
            application/json:
              schema:
                \$ref: '#/components/schemas/Pet'
    post:
      requestBody:
        content:
          application/json:
            schema:
              \$ref: '#/components/schemas/Pet'
  /pets/{id}:
    delete:
      responses:
        '204':
          description: gone
components:
  schemas:
    Pet:
      type: object
      properties:
        owner:
          \$ref: '#/components/schemas/Owner'
    Owner:
      type: object
''';

const _json = '''
{
  "swagger": "2.0",
  "info": { "title": "Legacy API" },
  "paths": {
    "/users": {
      "get": {
        "responses": { "200": { "schema": { "\$ref": "#/definitions/User" } } }
      }
    }
  },
  "definitions": { "User": { "type": "object" } }
}
''';

void main() {
  group('openapiToSpec', () {
    test('parses YAML: operations coloured by method + schema refs', () {
      final spec = openapiToSpec(_yaml);
      final byId = {for (final n in spec.nodes) n.id: n};

      // Operation nodes exist, coloured by method.
      expect(byId['op:GET /pets']!.fill, '#DAE8FC');
      expect(byId['op:POST /pets']!.fill, '#D5E8D4');
      expect(byId['op:DELETE /pets/{id}']!.fill, '#F8CECC');

      // Schema nodes exist.
      expect(byId.containsKey('schema:Pet'), isTrue);
      expect(byId.containsKey('schema:Owner'), isTrue);

      bool edge(String a, String b) => spec.edges.any((e) => e.from == a && e.to == b);
      expect(edge('op:GET /pets', 'schema:Pet'), isTrue);
      expect(edge('op:POST /pets', 'schema:Pet'), isTrue);
      // schema → schema via nested $ref
      expect(edge('schema:Pet', 'schema:Owner'), isTrue);
    });

    test('parses Swagger 2.0 JSON with definitions', () {
      final spec = openapiToSpec(_json);
      final ids = spec.nodes.map((n) => n.id).toSet();
      expect(ids, containsAll(<String>['op:GET /users', 'schema:User']));
      expect(spec.edges.any((e) => e.from == 'op:GET /users' && e.to == 'schema:User'),
          isTrue);
      expect(spec.title, 'Legacy API');
    });

    test('builds a valid round-trip .vsdx', () {
      final bytes = openapiToSpec(_yaml).build();
      final doc = const DocumentParser().parse(bytes);
      expect(doc.pages.single.shapes.where((s) => !s.is1D).length, greaterThan(3));
      expect(validateDocument(doc).where((i) => i.severity == 'error'), isEmpty);
    });
  });
}
