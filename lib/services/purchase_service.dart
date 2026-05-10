import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import '../config/billing_config.dart';

class PurchaseService extends ChangeNotifier {
  static const String premiumMonthlyId = BillingConfig.premiumSubscriptionId;
  static const Set<String> _productIds = {premiumMonthlyId};

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _subscription;

  bool _available = false;
  bool _loading = true;
  bool _purchasePending = false;
  String? _errorMessage;
  List<ProductDetails> _products = [];
  void Function()? _onPremiumUnlocked;

  bool get available => _available;
  bool get loading => _loading;
  bool get purchasePending => _purchasePending;
  String? get errorMessage => _errorMessage;
  ProductDetails? get premiumProduct =>
      _products.where((p) => p.id == premiumMonthlyId).firstOrNull;
  String get premiumPrice => premiumProduct?.price ?? '';

  Future<void> init({required void Function() onPremiumUnlocked}) async {
    _onPremiumUnlocked = onPremiumUnlocked;
    _subscription ??= _iap.purchaseStream.listen(
      _handlePurchases,
      onDone: () => _subscription?.cancel(),
      onError: (error) {
        _errorMessage = 'Achat indisponible pour le moment.';
        _purchasePending = false;
        notifyListeners();
      },
    );
    await loadProducts();
  }

  Future<void> loadProducts() async {
    _loading = true;
    _errorMessage = null;
    notifyListeners();

    _available = await _iap.isAvailable();
    if (!_available) {
      _products = [];
      _loading = false;
      _errorMessage = 'Google Play Billing est indisponible sur cet appareil.';
      notifyListeners();
      return;
    }

    final response = await _iap.queryProductDetails(_productIds);
    _products = response.productDetails;
    _loading = false;

    if (response.error != null) {
      _errorMessage = response.error!.message;
    } else if (_products.isEmpty) {
      _errorMessage =
          'Produit Premium introuvable. Configurez $premiumMonthlyId dans Google Play Console.';
    }
    notifyListeners();
  }

  Future<void> buyPremium() async {
    final product = premiumProduct;
    if (product == null) {
      await loadProducts();
      if (premiumProduct == null) return;
    }
    _purchasePending = true;
    _errorMessage = null;
    notifyListeners();

    final param = PurchaseParam(productDetails: premiumProduct!);
    await _iap.buyNonConsumable(purchaseParam: param);
  }

  Future<void> restorePurchases() async {
    _purchasePending = true;
    _errorMessage = null;
    notifyListeners();
    await _iap.restorePurchases();
    Future<void>.delayed(const Duration(seconds: 3), () {
      if (!_purchasePending) return;
      _purchasePending = false;
      _errorMessage = 'Aucun abonnement Premium restauré.';
      notifyListeners();
    });
  }

  Future<void> _handlePurchases(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.productID != premiumMonthlyId) continue;

      if (purchase.status == PurchaseStatus.pending) {
        _purchasePending = true;
      } else if (purchase.status == PurchaseStatus.error) {
        _errorMessage = purchase.error?.message ?? 'Achat refusé.';
        _purchasePending = false;
      } else if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        _onPremiumUnlocked?.call();
        _purchasePending = false;
      } else if (purchase.status == PurchaseStatus.canceled) {
        _purchasePending = false;
      }

      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }
    }
    if (purchases.isEmpty) {
      _purchasePending = false;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
