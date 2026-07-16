class Vec2 {
  final double x, y;
  const Vec2(this.x, this.y);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Vec2 &&
          runtimeType == other.runtimeType &&
          (x - other.x).abs() < 0.001 &&
          (y - other.y).abs() < 0.001;

  @override
  int get hashCode => x.hashCode ^ y.hashCode;

  double distanceTo(Vec2 other) {
    return (x - other.x) * (x - other.x) + (y - other.y) * (y - other.y);
  }
}
