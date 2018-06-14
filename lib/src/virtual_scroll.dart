library virtual_scroll.core;

import 'dart:async';
import 'dart:html';
import 'dart:math' as Math;
import 'package:angular/angular.dart';

@Component(
    selector: 'virtual-scroll',
    styleUrls: const ["virtual_scroll.css"],
    templateUrl: "virtual_scroll.html",
    preserveWhitespace: false,
    directives: const [coreDirectives])
class VirtualScrollComponent implements OnInit, OnChanges, OnDestroy {
  @HostBinding('style.overflow-y')
  String get overflowY => parentScroll != null ? 'hidden' : 'auto';

  // Streams
  //////////
  final _update = new StreamController<List>();
  final _changeController = new StreamController<ChangeEvent>();
  final _startController = new StreamController<ChangeEvent>();
  final _endController = new StreamController<ChangeEvent>();
  StreamSubscription<Event> _resizeSubscription;
  StreamSubscription<Event> _scrollSubscription;

  // Outputs
  //////////
  @Output()
  Stream<ChangeEvent> get change => _changeController.stream;

  @Output()
  Stream<ChangeEvent> get start => _startController.stream;

  @Output()
  Stream<ChangeEvent> get end => _endController.stream;

  @Output()
  Stream<List> get update => _update.stream;

  // Inputs
  /////////
  @Input()
  List items = [];

  @Input()
  num scrollbarWidth;

  @Input()
  num scrollbarHeight;

  @Input()
  num childWidth;

  @Input()
  num childHeight;

  @Input()
  num bufferAmount = 0;

  @Input()
  set parentScroll(Element el) {
    if (_parentScroll != el) {
      _parentScroll = el;
      _addParentEventHandlers(el);
    }
  }

  // ViewChilds
  /////////////
  @ViewChild('shim')
  Element shimElement;

  @ViewChild('content')
  Element contentElement;

  @ContentChild('container')
  Element containerElement;

  // Public
  //////////
  Element get parentScroll => _parentScroll;
  List viewPortItems = [];

  // Private
  //////////
  num _previousStart;
  num _previousEnd;
  bool _startupLoop = true;
  Element _parentScroll;
  num _lastScrollHeight = -1;
  num _lastTopPadding = -1;
  _Dimensions _d;

  // Providers
  ////////////
  final HtmlElement element;
  final NgZone zone;

  VirtualScrollComponent(this.element, this.zone);

  // Methods
  //////////
  @override
  void ngOnInit() {
    scrollbarWidth =
        0; // this.element.nativeElement.offsetWidth - this.element.nativeElement.clientWidth;
    scrollbarHeight =
        0; // this.element.nativeElement.offsetHeight - this.element.nativeElement.clientHeight;

    if (_parentScroll == null) {
      _addParentEventHandlers(element);
    }
  }

  @override
  void ngOnDestroy() {
    _update.close();
    _startController.close();
    _endController.close();
    _changeController.close();
    _removeParentEventHandlers();
  }

  @override
  void ngOnChanges(Map<String, SimpleChange> changes) {
    _previousStart = null;
    _previousEnd = null;
    final change = changes["items"] ?? new SimpleChange(null, null);
    if (changes["items"] != null && change.previousValue == null ||
        (change.previousValue != null &&
            (change.previousValue as List).isEmpty)) {
      _startupLoop = true;
      _d = null;
    }
    _refresh();
  }

  void _refresh({bool forceViewportUpdate: false}) {
    zone.runOutsideAngular(() => window.requestAnimationFrame(
        (_) => _calculateItems(forceViewportUpdate: forceViewportUpdate)));
  }

  void _calculateItems({bool forceViewportUpdate: false}) {
    final el = parentScroll ?? element;

    _d ??= _calculateDimensions();
    final its = items ?? [];
    final offsetTop = _getElementsOffset();
    var elScrollTop = el.scrollTop;

    if (elScrollTop > _d.scrollHeight) {
      elScrollTop = _d.scrollHeight + offsetTop;
    }

    final scrollTop = Math.max<num>(0, elScrollTop - offsetTop);
    final indexByScrollTop =
        scrollTop / _d.scrollHeight * _d.itemCount / _d.itemsPerRow;
    var endIndex = Math.min<num>(
        _d.itemCount,
        indexByScrollTop.ceil() * _d.itemsPerRow +
            _d.itemsPerRow * (_d.itemsPerCol + 1));

    var maxStartEnd = endIndex;
    final modEnd = endIndex % _d.itemsPerRow;
    if (modEnd != 0) {
      maxStartEnd = endIndex + _d.itemsPerRow - modEnd;
    }
    final maxStart = Math.max<num>(
        0, maxStartEnd - _d.itemsPerCol * _d.itemsPerRow - _d.itemsPerRow);
    num startIndex =
        Math.min(maxStart, indexByScrollTop.floor() * _d.itemsPerRow);

    final topPadding = its.isEmpty
        ? 0
        : (_d.childHeight * (startIndex / _d.itemsPerRow).ceil() -
            (_d.childHeight * Math.min<num>(startIndex, bufferAmount)));

    if (topPadding != _lastTopPadding) {
      final el = contentElement;
      el.style.transform = "translateY(${topPadding}px)";
      _lastTopPadding = topPadding;
    }

    startIndex = !startIndex.isNaN ? startIndex : -1;
    endIndex = !endIndex.isNaN ? endIndex : -1;
    startIndex -= bufferAmount;
    startIndex = Math.max(0, startIndex);
    endIndex += bufferAmount;
    endIndex = Math.min(its.length, endIndex);
    if (startIndex != _previousStart ||
        endIndex != _previousEnd ||
        forceViewportUpdate == true) {
      zone.run(() {
        // update the scroll list
        final _end = endIndex >= 0
            ? endIndex
            : 0; // To prevent from accidentally selecting the entire array with a negative 1 (-1) in the end position.
        viewPortItems = its.sublist(startIndex, _end);
        _update.add(viewPortItems);

        // emit 'start' event
        if (startIndex != _previousStart && _startupLoop == false) {
          _startController.add(new ChangeEvent(startIndex, endIndex));
        }

        // emit 'end' event
        if (endIndex != _previousEnd && _startupLoop == false) {
          _endController.add(new ChangeEvent(startIndex, endIndex));
        }

        _previousStart = startIndex;
        _previousEnd = endIndex;

        if (_startupLoop == true) {
          _refresh();
        } else {
          _changeController.add(new ChangeEvent(startIndex, endIndex));
        }
      });
    } else if (_startupLoop == true) {
      _startupLoop = false;
      _refresh();
    }
  }

  void _addParentEventHandlers(el) {
    _removeParentEventHandlers();
    if (el != null) {
      zone.runOutsideAngular(() {
        _scrollSubscription = el.onScroll.listen((_) => _refresh());
        _resizeSubscription = el.onResize.listen((_) {
          _d = null;
          _refresh();
        });
      });
    }
  }

  void _removeParentEventHandlers() {
    _scrollSubscription?.cancel();
    _scrollSubscription = null;
    _resizeSubscription?.cancel();
    _resizeSubscription = null;
  }

  void scrollToIndex(int index) {
    _d ??= _calculateDimensions();
    final scrollTop = ((index / _d.itemsPerRow).floor() * _d.childHeight) -
        (_d.childHeight * Math.min(index, bufferAmount));

    element.scrollTop = scrollTop;
  }

  void scrollToItem(item) {
    final index = (items ?? []).indexOf(item);
    if (index < 0 || index >= (items ?? []).length) return;

    scrollToIndex(index);
  }

  num _getElementsOffset() {
    var offsetTop = 0;
    if (containerElement != null) {
      offsetTop += containerElement.offsetTop;
    }
    if (parentScroll != null) {
      offsetTop += element.offsetTop;
    }
    return offsetTop;
  }

  int _getElementHeight(Element el) =>
      el.clientHeight == 0 ? el.offsetHeight : 0;

  int _getElementWidth(Element el) => el.clientWidth == 0 ? el.offsetWidth : 0;

  _Dimensions _calculateDimensions() {
    final el = parentScroll ?? element;
    final its = items ?? [];
    final itemCount = its.length;
    var viewWidth = _getElementWidth(el) - scrollbarWidth;
    var viewHeight = _getElementHeight(el) - scrollbarHeight;

    var contentDimensions;
    if (childWidth == null || childHeight == null) {
      var content = contentElement;
      if (containerElement != null) {
        content = containerElement;
      }
      contentDimensions = content.children.isNotEmpty
          ? content.children[0].getBoundingClientRect()
          : new Rectangle<num>(0, 0, viewWidth, viewHeight);
    }
    final _childWidth = childWidth ?? contentDimensions.width;
    final _childHeight = childHeight ?? contentDimensions.height;

    final itemsPerRow = Math.max<num>(1, (viewWidth / _childWidth).floor());
    final itemsPerCol = Math.max<num>(1, (viewHeight / _childHeight).floor());
    final scrollHeight = _childHeight * (itemCount / itemsPerRow).ceil();
    if (scrollHeight != _lastScrollHeight) {
      shimElement.style.height = '${scrollHeight}px';
      _lastScrollHeight = scrollHeight;
    }

    return new _Dimensions()
      ..itemCount = itemCount
      ..viewWidth = viewWidth
      ..viewHeight = viewHeight
      ..childWidth = _childWidth
      ..childHeight = _childHeight
      ..itemsPerRow = itemsPerRow
      ..itemsPerCol = itemsPerCol
      ..scrollHeight = scrollHeight;
  }
}

class ChangeEvent {
  final num start;
  final num end;

  ChangeEvent(this.start, this.end);
}

class _Dimensions {
  num itemCount;
  num viewWidth;
  num viewHeight;
  num childWidth;
  num childHeight;
  num itemsPerRow;
  num itemsPerCol;
  num scrollHeight;
}
