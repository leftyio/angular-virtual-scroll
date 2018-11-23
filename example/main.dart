import 'dart:html';

import 'package:angular/angular.dart';
import 'package:angular_virtual_scroll/angular_virtual_scroll.dart';

// ignore: uri_has_not_been_generated
import 'main.template.dart' as ng;

void main() {
  runApp(ng.AppComponentNgFactory);
}

@Component(
  selector: "demo-app",
  templateUrl: "template.html",
  styleUrls: ['template.css'],
  directives: [VirtualScrollComponent, NgFor, ItemComponent],
)
class AppComponent {
  List<Item> items = []; // large list.
  List<Item> viewPortItems; // partial list.

  AppComponent() {
    for (int i = 0; i < 100; i++) items.add(Item("Robot", i));
  }
  void add() {
    final newList = items.toList();
    newList.add(Item("Robot", items.length));
    items = newList;
  }

  void onEnd(ChangeEvent e) {
    if (e.end > items.length - 10) {
      final newList = items.toList();
      newList.addAll(
        List.generate(25, (idx) => Item('Robot', items.length + idx)),
      );
      items = newList;
    }
  }
}

class Item {
  final String name;
  final int index;
  Item(this.name, this.index);
}

@Component(
  selector: 'item',
  template: '''
<div>
  <span>Label : {{ item.name }}</span>
  <span>Index : {{ item.index }}</span>
</div>
''',
)
class ItemComponent {
  ItemComponent(this.element);

  final Element element;

  Item _item;

  Item get item => _item;

  @Input()
  set item(Item val) {
    _item = val;

    if (item.index % 2 == 0) {
      element.style.backgroundColor = 'rgba(0, 0, 255, 0.1)';
    } else {
      element.style.backgroundColor = 'rgba(255, 0, 0, 0.1)';
    }
  }
}
