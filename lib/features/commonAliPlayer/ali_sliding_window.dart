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
  final Set<int> _executedIndices = {};
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
    _itemList
      ..clear()
      ..addAll(items);
  }

  void addItems(List<T> items) {
    _itemList.addAll(items);
  }

  void moveTo(int position, {bool preserveExecutedItems = false}) {
    if (position < 0 || position >= _itemList.length) return;
    if (_currentIndex == position) return;

    final currentWindow = getWindowIndices(position);
    if (currentWindow.isEmpty) return;

    final previousWindow = getWindowIndices(_currentIndex);
    final toLoad = _difference(currentWindow, previousWindow);
    final toCancel = preserveExecutedItems
        ? <int>[]
        : _difference(previousWindow, currentWindow);

    _processItems(toCancel, _cancelItem);
    _processItems(toLoad, _executeItem);

    _currentIndex = position;
  }

  void _processItems(List<int> indices, void Function(int index) processor) {
    for (final index in indices) {
      processor(index);
    }
  }

  void _cancelItem(int index) {
    if (!_executedIndices.contains(index)) return;
    _executedIndices.remove(index);

    final item = _itemList[index];
    if (isValid(item)) {
      cancel?.call(item);
    }
  }

  void _executeItem(int index) {
    if (_executedIndices.contains(index)) return;

    final item = _itemList[index];
    if (!isValid(item)) return;

    _executedIndices.add(index);
    execute(item);
  }

  List<int> getWindowIndices(int position) {
    if (position < 0 || position >= _itemList.length) return [];
    final windowIndices = <int>[];
    for (var offset in _windowItems) {
      final index = position + offset;
      if (index >= 0 && index < _itemList.length) {
        windowIndices.add(index);
      }
    }
    return windowIndices;
  }

  void release() {
    cancelAll();
    _currentIndex = -1;
  }

  void cancelAll() {
    for (final index in _executedIndices.toList()) {
      final item = _itemList[index];
      if (isValid(item)) {
        cancel?.call(item);
      }
    }
    _executedIndices.clear();
    _itemList.clear();
  }

  int getCurrentPosition() => _currentIndex;

  static List<int> _getWindowRange(int leftWindowSize, int rightWindowSize) {
    final totalSize = leftWindowSize + rightWindowSize + 1;
    return List.generate(totalSize, (i) => i - leftWindowSize);
  }

  List<int> _difference(List<int> list1, List<int> list2) {
    final set2 = Set.from(list2);
    return list1.where((item) => !set2.contains(item)).toList();
  }
}
