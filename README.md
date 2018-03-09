virtual-scroll for AngularDart
==============================


## Description

This component scrolls the large list in the browser.

I referred to the TypeScript version.<br>
https://github.com/rintoj/angular2-virtual-scroll

## Demo

Live demo.<br>
https://takutaro.github.io/angular-virtual-scroll-demo/build/web/

## Requirement

* Dart >= 1.24
* AngularDart >= 4.0.0 <5.0.0"
* Modern browser

## Usage

See the following sample code.<br>
https://github.com/takutaro/angular-virtual-scroll-demo/

Surround the content you want to scroll with the \<virtual-scroll\> tag.
* Specify your large list to [items].
* Prepare a partial list. This list is set by (update).
* Specify width and height with style.

```html
<virtual-scroll [items]="items" (update)="viewPortItems=\$event" style="width:auto; height:75vh;">
  <div *ngFor="let item of viewPortItems;">
      {{item.name}} Hello.
  </div>
</virtual-scroll>
<button (click)="add()">ADD</button>
```
Import the required package.

```Dart
import 'package:angular/angular.dart';
import 'package:virtual_scroll/virtual_scroll.dart';
```

Angular component:

```Dart
@Component(...)
class AppComponent {

  List<Item> items = []; // large list.
  List<Item> viewPortItems; // partial list.

  AppComponent() {
    for (int i = 0; i < 10000; i++) items.add(new Item("Robot $i"));
  }
  void add() {
    items.add(new Item("New Robot"));
    items = items.toList(); // Make new list to detect changes.
  }
}
```

## Author

takutaro.

## License

The MIT License (MIT).
