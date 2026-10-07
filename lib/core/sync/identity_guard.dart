/// Prevents reconnecting from replacing an identity that already owns records.
class IdentityGuard {
  static String? check(
    String? activeOwner, {
    String? rememberedOwner,
    Iterable<String> cachedOwners = const [],
  }) {
    if (activeOwner == null) {
      if (rememberedOwner != null || cachedOwners.isNotEmpty) {
        throw StateError('原账户会话待恢复，已保留本地记录。');
      }
      return null;
    }
    if (rememberedOwner != null && activeOwner != rememberedOwner ||
        rememberedOwner == null &&
            cachedOwners.isNotEmpty &&
            !cachedOwners.contains(activeOwner)) {
      throw StateError('当前身份与原账户不一致，已暂停连接。');
    }
    return activeOwner;
  }
}
