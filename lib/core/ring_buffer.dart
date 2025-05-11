class RingBuffer<T> {
  final int size;
  final List<T?> _buffer;
  int _index = 0;
  int _count = 0;

  RingBuffer(this.size)
      : _buffer = List<T?>.filled(size, null, growable: false);

  void add(T item) {
    _buffer[_index] = item;
    _index = (_index + 1) % size;
    if (_count < size) _count++;
  }

  List<T?> get buffer => _buffer;

  List<T> toList() {
    final list = <T>[];
    for (int i = 0; i < _count; i++) {
      final idx = (_index - _count + i + size) % size;
      list.add(_buffer[idx]!);
    }
    return list;
  }

  T? get last {
    return _buffer[_index - 1];
  }
}
