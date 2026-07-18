import 'package:test/test.dart';
import 'package:vsdx/agent.dart';
import 'package:vsdx/vsdx.dart';

const _ddl = '''
-- shop schema
CREATE TABLE customers (
  id INT PRIMARY KEY,
  name VARCHAR(100) NOT NULL,
  email VARCHAR(255)
);

CREATE TABLE orders (
  id INT PRIMARY KEY,
  customer_id INT NOT NULL REFERENCES customers(id),
  total DECIMAL(10,2),
  created_at TIMESTAMP
);

CREATE TABLE order_items (
  id INT,
  order_id INT,
  product_id INT,
  qty INT DEFAULT 1,
  PRIMARY KEY (id),
  CONSTRAINT fk_order FOREIGN KEY (order_id) REFERENCES orders(id),
  FOREIGN KEY (product_id) REFERENCES products(id)
);

CREATE TABLE products (
  id INT PRIMARY KEY,
  title VARCHAR(200)
);
''';

void main() {
  group('sqlToSpec', () {
    test('extracts tables, columns, PK/FK markers', () {
      final spec = sqlToSpec(_ddl);
      final byId = {for (final n in spec.nodes) n.id: n};
      expect(byId.keys, containsAll(<String>['customers', 'orders', 'order_items', 'products']));

      // customers: id is PK.
      expect(byId['customers']!.text, contains('id (PK)'));
      expect(byId['customers']!.text, contains('email'));

      // orders: inline FK on customer_id.
      expect(byId['orders']!.text, contains('customer_id (FK)'));

      // order_items: table-level PK + two FKs (one via CONSTRAINT).
      expect(byId['order_items']!.text, contains('id (PK)'));
      expect(byId['order_items']!.text, contains('order_id (FK)'));
      expect(byId['order_items']!.text, contains('product_id (FK)'));
    });

    test('creates FK edges to referenced tables', () {
      final spec = sqlToSpec(_ddl);
      bool edge(String from, String to) =>
          spec.edges.any((e) => e.from == from && e.to == to);
      expect(edge('orders', 'customers'), isTrue);
      expect(edge('order_items', 'orders'), isTrue);
      expect(edge('order_items', 'products'), isTrue);
      // FK column is used as the edge label.
      final e = spec.edges.firstWhere((e) => e.from == 'orders');
      expect(e.label, 'customer_id');
    });

    test('builds a valid, round-trip ER .vsdx', () {
      final bytes = sqlToSpec(_ddl).build();
      final doc = const DocumentParser().parse(bytes);
      final page = doc.pages.single;
      expect(page.shapes.where((s) => !s.is1D), hasLength(4)); // 4 tables
      expect(page.shapes.where((s) => s.is1D), hasLength(3)); // 3 FKs
      expect(validateDocument(doc).where((i) => i.severity == 'error'), isEmpty);
    });

    test('ignores backticked/quoted identifiers and schema prefixes', () {
      final spec = sqlToSpec('''
        CREATE TABLE `app`.`user` (
          `id` INT PRIMARY KEY,
          `role_id` INT REFERENCES `role`(`id`)
        );
        CREATE TABLE "role" ( "id" INT PRIMARY KEY );
      ''');
      final ids = spec.nodes.map((n) => n.id).toSet();
      expect(ids, containsAll(<String>['user', 'role']));
      expect(spec.edges.any((e) => e.from == 'user' && e.to == 'role'), isTrue);
    });
  });
}
