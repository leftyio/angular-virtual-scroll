library virtual_scroll.core;

import 'dart:async';
import 'dart:html';
import 'dart:math' as Math;
import 'package:angular/angular.dart';

@Component(
  selector: 'virtual-scroll',
  styleUrls: ["virtual_scroll.css"],
  templateUrl: "virtual_scroll.html",
  changeDetection: ChangeDetectionStrategy.OnPush,
)
class VirtualScrollComponent implements OnInit, OnDestroy {
  // Streams
  //////////
  final _update = StreamController<List>();
  final _changeController = StreamController<ChangeEvent>();
  final _startController = StreamController<ChangeEvent>();
  final _endController = StreamController<ChangeEvent>();

  StreamSubscription _resizeSubscription;
  StreamSubscription _scrollSubscription;

  @HostBinding('class.parent-scroll')
  bool get hasParentScroll => parentScroll != null;

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
  List _items = [];

  @Input()
  set items(List values) {
    _previousStart = null;
    _previousEnd = null;
    _contentInitialized = false;
    _cachedDimensions = null;
    if (values?.isNotEmpty == true) {
      _startupLoop = true;
    }
    _items = values;
    _refresh();
  }

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
  set parentScroll(dynamic /*Window|Element*/ el) {
    if (_parentScroll != el) {
      _parentScroll = el;
      _addParentEventHandlers(el);
    }
  }

  // ViewChilds
  /////////////
  @ViewChild('shim')
  Element shimElementRef;

  @ViewChild('content')
  Element contentElementRef;

  @ContentChild('container')
  Element containerElementRef;

  // Public
  //////////
  dynamic /*Window|Element*/ get parentScroll => _parentScroll;
  List viewPortItems = [];

  // Private
  //////////
  num _previousStart;
  num _previousEnd;
  bool _startupLoop = true;
  dynamic currentTween;
  dynamic /*Window|Element*/ _parentScroll;
  num _lastScrollHeight = -1;
  num _lastTopPadding = -1;

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

  void _refresh({bool forceViewportUpdate: false}) => zone.runOutsideAngular(
        () => window.requestAnimationFrame(
              (_) => _calculateItems(forceViewportUpdate: forceViewportUpdate),
            ),
      );

  num _calculScrollTop(Element el, _Dimensions dimensions) {
    final offsetTop = _getElementsOffset();

    var elScrollTop = parentScroll is Window
        ? (window.pageYOffset ??
            document.documentElement.scrollTop ??
            document.body.scrollTop ??
            0)
        : el.scrollTop;

    if (elScrollTop > dimensions.scrollHeight) {
      elScrollTop = dimensions.scrollHeight + offsetTop;
    }

    return Math.max<num>(0, elScrollTop - offsetTop);
  }

  void _refreshTranslate(List its, _Dimensions dimensions, int startIndex) {
    final topPadding = its.isEmpty
        ? 0
        : (dimensions.childHeight *
                (startIndex / dimensions.itemsPerRow).ceil() -
            (dimensions.childHeight * Math.min<num>(startIndex, bufferAmount)));

    if (topPadding != _lastTopPadding) {
      contentElementRef.style.transform = "translateY(${topPadding}px)";
      _lastTopPadding = topPadding;
    }
  }

  num _getEndIndex(
      num indexByScrollTop, List its, _Dimensions dimensions, int scrollTop) {
    var idx = Math.min<num>(
        dimensions.itemCount,
        indexByScrollTop.ceil() * dimensions.itemsPerRow +
            dimensions.itemsPerRow * (dimensions.itemsPerCol + 1));

    idx = !idx.isNaN ? idx : -1;
    idx += bufferAmount;
    idx = Math.min(its.length, idx);
    return idx;
  }

  num _getStartIndex(
      num indexByScrollTop, int endIndex, _Dimensions dimensions) {
    var maxStartEnd = endIndex;
    final modEnd = endIndex % dimensions.itemsPerRow;
    if (modEnd != 0) {
      maxStartEnd = endIndex + dimensions.itemsPerRow - modEnd;
    }
    final maxStart = Math.max<num>(
        0,
        maxStartEnd -
            dimensions.itemsPerCol * dimensions.itemsPerRow -
            dimensions.itemsPerRow);
    var idx =
        Math.min(maxStart, indexByScrollTop.floor() * dimensions.itemsPerRow);

    idx = !idx.isNaN ? idx : -1;
    idx -= bufferAmount;
    idx = Math.max(0, idx);
    return idx;
  }

  void _calculateItems({bool forceViewportUpdate: false}) {
    if (_cachedDimensions == null || _contentInitialized == false) {
      _precalculateDimensions();
    }

    NgZone.assertNotInAngularZone();

    final el = parentScroll is Window ? document.body : parentScroll ?? element;
    final its = _items ?? [];

    _applyScrollHeight();
    final dimensions = _cachedDimensions;

    final scrollTop = _calculScrollTop(el, dimensions);

    final indexByScrollTop = scrollTop /
        dimensions.scrollHeight *
        dimensions.itemCount /
        dimensions.itemsPerRow;

    final endIndex = _getEndIndex(indexByScrollTop, its, dimensions, scrollTop);
    final startIndex = _getStartIndex(indexByScrollTop, endIndex, dimensions);

    _refreshTranslate(its, dimensions, startIndex);

    if (startIndex != _previousStart ||
        endIndex != _previousEnd ||
        forceViewportUpdate == true) {
      zone.run(() => _updateView(its, startIndex, endIndex));
    } else if (_startupLoop == true) {
      _startupLoop = false;
      _refresh();
    }
  }

  void _updateView(List items, int startIndex, int endIndex) {
// update the scroll list
    viewPortItems = items.sublist(startIndex, endIndex);
    _update.add(viewPortItems);

    final event = ChangeEvent(startIndex, endIndex);

    // emit 'start' event
    if (startIndex != _previousStart && _startupLoop == false) {
      _startController.add(event);
    }

    // emit 'end' event
    if (endIndex != _previousEnd && _startupLoop == false) {
      _endController.add(event);
    }

    _previousStart = startIndex;
    _previousEnd = endIndex;

    if (_startupLoop == true) {
      _refresh();
    } else {
      _changeController.add(event);
    }
  }

  void _addParentEventHandlers(el) {
    _removeParentEventHandlers();
    if (el != null) {
      _scrollSubscription = el.onScroll.listen((_) => _refresh());
      _resizeSubscription = el.onResize.listen((_) => () {
            _cachedDimensions = null;
            _contentInitialized = false;
            _refresh();
          });
    }
  }

  void _removeParentEventHandlers() {
    _scrollSubscription?.cancel();
    _scrollSubscription = null;
    _resizeSubscription?.cancel();
    _resizeSubscription = null;
  }

  void scrollTo(item) {
    final index = (_items ?? []).indexOf(item);
    if (index < 0 || index >= (_items ?? []).length) return;

    final d = _cachedDimensions;
    final scrollTop = ((index / d.itemsPerRow).floor() * d.childHeight) -
        (d.childHeight * Math.min(index, bufferAmount));

    element.scrollTop = scrollTop;
  }

  num _getElementsOffset() {
    var offsetTop = 0;
    if (containerElementRef != null) {
      offsetTop += containerElementRef.offsetTop;
    }
    if (parentScroll != null) {
      offsetTop += element.offsetTop;
    }
    return offsetTop;
  }

  _Dimensions _cachedDimensions;
  bool _contentInitialized = false;

  void _precalculateDimensions() {
    final el =
        parentScroll is Window ? document.body : (parentScroll ?? element);
    final its = _items ?? [];
    final itemCount = its.length;
    var viewWidth = el.clientWidth - scrollbarWidth;
    var viewHeight = el.clientHeight - scrollbarHeight;

    Rectangle contentDimensions;
    if (childWidth == null || childHeight == null) {
      var content = contentElementRef;
      if (containerElementRef != null) {
        content = containerElementRef;
      }

      if (content?.children?.isNotEmpty == true) {
        contentDimensions = content.children[0].getBoundingClientRect();
        _contentInitialized = true;
      } else {
        contentDimensions = Rectangle<num>(0, 0, viewWidth, viewHeight);
      }
    }
    final _childWidth = childWidth ?? contentDimensions.width;
    final _childHeight = childHeight ?? contentDimensions.height;

    final itemsPerRow = Math.max<num>(1, (viewWidth / _childWidth).floor());
    final itemsPerCol = Math.max<num>(1, (viewHeight / _childHeight).floor());
    final scrollHeight = _childHeight * (itemCount / itemsPerRow).ceil();

    _cachedDimensions = _Dimensions()
      ..itemCount = itemCount
      ..viewHeight = viewHeight
      ..viewWidth = viewWidth
      ..scrollHeight = scrollHeight
      ..childHeight = _childHeight
      ..childWidth = _childWidth
      ..itemsPerCol = itemsPerCol
      ..itemsPerRow = itemsPerRow;
  }

  void _applyScrollHeight() {
    final d = _cachedDimensions;

    if (d.scrollHeight != _lastScrollHeight) {
      shimElementRef.style.height = '${d.scrollHeight}px';
      _lastScrollHeight = d.scrollHeight;
    }
  }
}

class ChangeEvent {
  final num start;
  final num end;

  ChangeEvent(this.start, this.end);

  @override
  String toString() => {
        'start': start,
        'end': end,
      }.toString();
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
