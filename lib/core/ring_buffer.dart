class RingBuffer<T> {
  final int size;
  final List<T?> _buffer;
  int _index = 0;
  int _count = 0;

  RingBuffer(this.size)
      : _buffer = List<T?>.filled(size, null, growable: false) {
    assert(size > 0, 'Buffer size must be greater than 0');
  }

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
      list.add(_buffer[idx] as T);
    }
    return list;
  }

  T? get last {
    if (_count == 0) return null;
    return _buffer[(_index - 1 + size) % size];
  }
}
