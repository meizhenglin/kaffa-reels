// Copyright © 2025 Alibaba Cloud. All rights reserved.
//
// Author: keria
// Date: 2025/2/28
// Brief: 滑动窗口模版类

/// A generic class that manages sliding window loading and cancellation for a collection of items.
class AliSlidingWindow<T> {
  final void Function(T item) execute;
  final void Function(T item)? cancel;
  final bool Function(T item) isValid;
  final String extra;
  final List<int> _windowItems;
  final List<T> _itemList = [];
  final Set<T> _executedItemSets = {};
  int _currentIndex = -1;

  AliSlidingWindow.withWindowSize(
    int leftWindowSize,
    int rightWindowSize,
    this.execute,
    this.cancel, {
    bool Function(T)? isValid,
    this.extra = '',
  })  : assert(leftWindowSize >= 0),
        assert(rightWindowSize >= 0),
        isValid = isValid ?? _defaultIsValid<T>(),
        _windowItems = _getWindowRange(leftWindowSize, rightWindowSize);

  AliSlidingWindow.withCustomItems(
    List<int> items,
    this.execute,
    this.cancel, {
    bool Function(T)? isValid,
    this.extra = '',
  })  : isValid = isValid ?? _defaultIsValid<T>(),
        _windowItems = List.from(items);

  static bool Function(T) _defaultIsValid<T>() => (T item) => true;

  void setItems(List<T> items) {
    cancelAll();
    _itemList.clear();
    for (var item in items) {
      if (isValid(item)) _itemList.add(item);
    }
  }

  void addItems(List<T> items) {
    for (var item in items) {
      if (isValid(item)) _itemList.add(item);
    }
  }

  void moveTo(int position) {
    if (position < 0 || position >= _itemList.length) return;
    if (_currentIndex == position) return;

    final currentWindow = getWindowIndices(position);
    if (currentWindow.isEmpty) return;

    final previousWindow = getWindowIndices(_currentIndex);
    final toLoad = _difference(currentWindow, previousWindow);
    final toCancel = _difference(previousWindow, currentWindow);

    _processItems(toCancel, _cancelItem);
    _processItems(toLoad, _executeItem);

    _currentIndex = position;
  }

  void _processItems(List<T> items, void Function(T item) processor) {
    for (var item in items) {
      if (item != null) processor(item);
    }
  }

  void _cancelItem(T item) {
    if (_executedItemSets.contains(item)) {
      _executedItemSets.remove(item);
      cancel?.call(item);
    }
  }

  void _executeItem(T item) {
    if (!_executedItemSets.contains(item)) {
      _executedItemSets.add(item);
      execute(item);
    }
  }

  List<T> getWindowIndices(int position) {
    if (position < 0 || position >= _itemList.length) return [];
    final windowIndices = <T>[];
    for (var offset in _windowItems) {
      final index = position + offset;
      if (index >= 0 && index < _itemList.length) {
        windowIndices.add(_itemList[index]);
      }
    }
    return windowIndices;
  }

  void release() {
    cancelAll();
    _currentIndex = -1;
  }

  void cancelAll() {
    for (var item in _executedItemSets) {
      cancel?.call(item);
    }
    _executedItemSets.clear();
    _itemList.clear();
  }

  int getCurrentPosition() => _currentIndex;

  static List<int> _getWindowRange(int leftWindowSize, int rightWindowSize) {
    final totalSize = leftWindowSize + rightWindowSize + 1;
    return List.generate(totalSize, (i) => i - leftWindowSize);
  }

  List<T> _difference(List<T> list1, List<T> list2) {
    final set2 = Set.from(list2);
    return list1.where((item) => !set2.contains(item)).toList();
  }
}
