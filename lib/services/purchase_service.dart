import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import '../config/billing_config.dart';
import '../models/subscription_tier.dart';
import 'entitlement_service.dart';

class PurchaseService extends ChangeNotifier {
  static const String plusMonthlyId = BillingConfig.plusSubscriptionId;
  static const String proMonthlyId = BillingConfig.proSubscriptionId;
  static const Set<String> _productIds = {plusMonthlyId, proMonthlyId};

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _subscription;

  bool _available = false;
  bool _loading = true;
  bool _purchasePending = false;
  String? _errorMessage;
  List<ProductDetails> _products = [];
  final Set<String> _ownedProductIds = {};
  Future<void> Function(EntitlementSnapshot entitlement)?
      _onEntitlementVerified;

  bool get available => _available;
  bool get loading => _loading;
  bool get purchasePending => _purchasePending;
  String? get errorMessage => _errorMessage;

  ProductDetails? _productFor(String id) =>
      _products.where((p) => p.id == id).firstOrNull;

  ProductDetails? productFor(SubscriptionTier tier) => switch (tier) {
        SubscriptionTier.plus => _productFor(plusMonthlyId),
        SubscriptionTier.pro => _productFor(proMonthlyId),
        SubscriptionTier.free => null,
      };

  String priceFor(SubscriptionTier tier) => productFor(tier)?.price ?? '';

  SubscriptionTier get ownedTier {
    if (_ownedProductIds.contains(proMonthlyId)) return SubscriptionTier.pro;
    if (_ownedProductIds.contains(plusMonthlyId)) return SubscriptionTier.plus;
    return SubscriptionTier.free;
  }

  Future<void> init({
    required Future<void> Function(EntitlementSnapshot entitlement)
        onEntitlementVerified,
  }) async {
    _onEntitlementVerified = onEntitlementVerified;
    _subscription = _iap.purchaseStream.listen(
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
          'Abonnements introuvables. Configurez $plusMonthlyId et $proMonthlyId dans Google Play Console.';
    }
    notifyListeners();
  }

  Future<void> buyTier(SubscriptionTier tier) async {
    var product = productFor(tier);
    if (product == null) {
      await loadProducts();
      product = productFor(tier);
      if (product == null) return;
    }
    _purchasePending = true;
    _errorMessage = null;
    notifyListeners();

    final param = PurchaseParam(productDetails: product);
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
      if (_ownedProductIds.isEmpty) {
        _errorMessage = 'Aucun abonnement restauré.';
      }
      notifyListeners();
    });
  }

  Future<void> _handlePurchases(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (!_productIds.contains(purchase.productID)) continue;
      var verified = false;

      if (purchase.status == PurchaseStatus.pending) {
        _purchasePending = true;
      } else if (purchase.status == PurchaseStatus.error) {
        _errorMessage = purchase.error?.message ?? 'Achat refusé.';
        _purchasePending = false;
      } else if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        try {
          final entitlement = await EntitlementService.verifyPurchase(
            productId: purchase.productID,
            purchaseToken: purchase.verificationData.serverVerificationData,
          );
          _ownedProductIds.add(purchase.productID);
          await _onEntitlementVerified?.call(entitlement);
          _purchasePending = false;
          verified = true;
        } catch (error) {
          _errorMessage = error.toString().replaceFirst('Exception: ', '');
          _purchasePending = false;
        }
      } else if (purchase.status == PurchaseStatus.canceled) {
        _purchasePending = false;
      }

      if (verified && purchase.pendingCompletePurchase) {
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
