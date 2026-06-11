class RingBuffer<T> {
  RingBuffer(this.capacity) : assert(capacity > 0);

  final int capacity;
  final List<T> _items = [];

  void add(T item) {
    if (_items.length == capacity) {
      _items.removeAt(0);
    }
    _items.add(item);
  }

  List<T> get values => List.unmodifiable(_items);

  int get length => _items.length;

  bool get isEmpty => _items.isEmpty;

  void clear() => _items.clear();
}
