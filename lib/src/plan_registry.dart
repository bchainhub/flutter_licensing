/// Maps numeric plan identifiers to display names.
final class PlanRegistry {
  final Map<int, String> _names = {};
  void bind(int planId, String name) {
    if (planId < 0 || name.trim().isEmpty) {
      throw ArgumentError('Plan ID and name must be valid');
    }
    _names[planId] = name.trim();
  }

  void unbind(int planId) => _names.remove(planId);
  String? getName(int planId) => _names[planId];
  bool hasName(int planId) => _names.containsKey(planId);
  Map<int, String> get bindings => Map.unmodifiable(_names);
}
