import 'package:test/test.dart';
import 'package:vsdx/agent.dart';
import 'package:vsdx/vsdx.dart';

const _compose = '''
services:
  web:
    image: nginx
    depends_on:
      - api
  api:
    image: myapi
    depends_on:
      db:
        condition: service_healthy
    volumes:
      - data:/var/lib
  db:
    image: postgres
    volumes:
      - data:/var/lib/postgresql
volumes:
  data:
''';

const _k8s = '''
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
spec:
  template:
    metadata:
      labels:
        app: web
    spec:
      volumes:
        - name: cfg
          configMap:
            name: web-config
      containers:
        - name: web
          envFrom:
            - secretRef:
                name: web-secret
---
apiVersion: v1
kind: Service
metadata:
  name: web-svc
spec:
  selector:
    app: web
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: web-config
---
apiVersion: v1
kind: Secret
metadata:
  name: web-secret
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: web-ing
spec:
  rules:
    - http:
        paths:
          - backend:
              service:
                name: web-svc
''';

void main() {
  group('iacToSpec — docker-compose', () {
    test('services, depends_on/links edges, named volumes', () {
      final spec = iacToSpec(_compose);
      final ids = spec.nodes.map((n) => n.id).toSet();
      expect(ids, containsAll(<String>['svc:web', 'svc:api', 'svc:db', 'vol:data']));
      bool edge(String a, String b) => spec.edges.any((e) => e.from == a && e.to == b);
      expect(edge('svc:web', 'svc:api'), isTrue); // depends_on list
      expect(edge('svc:api', 'svc:db'), isTrue); // depends_on map
      expect(edge('svc:api', 'vol:data'), isTrue); // mounted named volume
      expect(edge('svc:db', 'vol:data'), isTrue);
    });
  });

  group('iacToSpec — kubernetes', () {
    test('resources by kind + selector/ingress/volume edges', () {
      final spec = iacToSpec(_k8s);
      final ids = spec.nodes.map((n) => n.id).toSet();
      expect(
          ids,
          containsAll(<String>[
            'k8s:deployment/web',
            'k8s:service/web-svc',
            'k8s:configmap/web-config',
            'k8s:secret/web-secret',
            'k8s:ingress/web-ing',
          ]));
      bool edge(String a, String b) => spec.edges.any((e) => e.from == a && e.to == b);
      expect(edge('k8s:service/web-svc', 'k8s:deployment/web'), isTrue); // selector
      expect(edge('k8s:ingress/web-ing', 'k8s:service/web-svc'), isTrue); // backend
      expect(edge('k8s:deployment/web', 'k8s:configmap/web-config'), isTrue); // volume
      expect(edge('k8s:deployment/web', 'k8s:secret/web-secret'), isTrue); // envFrom
    });
  });

  test('both build valid round-trip .vsdx', () {
    for (final src in <String>[_compose, _k8s]) {
      final doc = const DocumentParser().parse(iacToSpec(src).build());
      expect(doc.pages.single.shapes.where((s) => !s.is1D), isNotEmpty);
      expect(validateDocument(doc).where((i) => i.severity == 'error'), isEmpty);
    }
  });
}
