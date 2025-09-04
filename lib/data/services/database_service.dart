// lib/data/services/database_service.dart - FIXED VERSION
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import 'package:moneysun/data/models/budget_model.dart';
import 'package:moneysun/data/models/partnership_model.dart';
import 'package:moneysun/data/models/transaction_model.dart';
import 'package:moneysun/data/models/wallet_model.dart';
import 'package:moneysun/data/models/report_data_model.dart';
import 'package:moneysun/data/models/category_model.dart';
import 'package:moneysun/data/providers/user_provider.dart';
import 'package:moneysun/data/services/local_database_service.dart';
import 'package:moneysun/data/services/offline_sync_service.dart';
import 'package:async/async.dart';
import 'package:collection/collection.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class DatabaseService {
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();
  final String? _uid = FirebaseAuth.instance.currentUser?.uid;
  final LocalDatabaseService _localDb = LocalDatabaseService();
  final OfflineSyncService _syncService = OfflineSyncService();

  static Future<void> enableOfflineSupport() async {
    FirebaseDatabase.instance.setPersistenceEnabled(true);
    FirebaseDatabase.instance.setPersistenceCacheSizeBytes(10000000);
  }

  // ============ ENHANCED TRANSACTION METHODS ============

  /// FIX: Enhanced offline-first transaction creation
  Future<void> addTransaction(TransactionModel transaction) async {
    if (_uid == null) return;

    try {
      // Generate unique ID if not provided
      final transactionId = transaction.id.isEmpty
          ? DateTime.now().millisecondsSinceEpoch.toString()
          : transaction.id;

      final transactionWithId = TransactionModel(
        id: transactionId,
        amount: transaction.amount,
        type: transaction.type,
        categoryId: transaction.categoryId,
        walletId: transaction.walletId,
        date: transaction.date,
        description: transaction.description,
        userId: transaction.userId,
        subCategoryId: transaction.subCategoryId,
        transferToWalletId: transaction.transferToWalletId,
      );

      // Always save locally first (offline-first approach)
      await _syncService.addTransactionOffline(transactionWithId);

      // Save description to history with context
      if (transaction.description.isNotEmpty) {
        await _syncService.saveDescriptionWithContext(
          _uid!,
          transaction.description,
          type: transaction.type,
          categoryId: transaction.categoryId,
          amount: transaction.amount,
        );
      }

      print('✅ Transaction added offline-first: $transactionId');
    } catch (e) {
      print("❌ Error adding transaction: $e");
      rethrow;
    }
  }

  /// FIX: Enhanced wallet creation with offline support
  Future<void> addWalletOffline(
    String name,
    double initialBalance,
    String ownerId,
  ) async {
    if (_uid == null) return;

    try {
      final newWallet = Wallet(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name,
        balance: initialBalance,
        ownerId: ownerId,
        isVisibleToPartner: true,
      );

      await _syncService.addWalletOffline(newWallet);
      print('✅ Wallet added offline-first: ${newWallet.id}');
    } catch (e) {
      print("❌ Error adding wallet offline: $e");
      rethrow;
    }
  }

  /// FIX: Enhanced category creation with offline support
  Future<void> addCategoryOffline(String name, String type) async {
    if (_uid == null) return;

    try {
      final newCategory = Category(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name,
        ownerId: _uid!,
        type: type,
      );

      await _syncService.addCategoryOffline(newCategory);
      print('✅ Category added offline-first: ${newCategory.id}');
    } catch (e) {
      print("❌ Error adding category offline: $e");
      rethrow;
    }
  }

  // ============ ENHANCED WALLET METHODS ============

  /// FIX: Get wallets with offline fallback
  Stream<List<Wallet>> getWalletsStream(UserProvider userProvider) {
    if (_uid == null) return Stream.value([]);

    // Start with offline data
    final controller = StreamController<List<Wallet>>();
    bool hasEmittedOfflineData = false;

    // Load offline data first
    _loadOfflineWallets(userProvider).then((offlineWallets) {
      if (offlineWallets.isNotEmpty) {
        controller.add(offlineWallets);
        hasEmittedOfflineData = true;
      }
    });

    // Setup Firebase stream
    StreamSubscription? firebaseSubscription;

    if (userProvider.partnershipId == null || userProvider.partnerUid == null) {
      // Single user wallet stream
      final walletRef = _dbRef
          .child('wallets')
          .orderByChild('ownerId')
          .equalTo(_uid);

      firebaseSubscription = walletRef.onValue.listen(
        (event) {
          final List<Wallet> wallets = [];
          if (event.snapshot.exists) {
            final walletMap = event.snapshot.value as Map<dynamic, dynamic>;
            walletMap.forEach((key, value) {
              final snapshot = event.snapshot.child(key);
              wallets.add(Wallet.fromSnapshot(snapshot));
            });
          }
          controller.add(wallets);
        },
        onError: (error) {
          print('❌ Firebase wallet stream error: $error');
          if (!hasEmittedOfflineData) {
            _loadOfflineWallets(userProvider).then((offlineWallets) {
              controller.add(offlineWallets);
            });
          }
        },
      );
    } else {
      // Partnership wallet stream
      final pId = userProvider.partnershipId!;
      final partnerUid = userProvider.partnerUid!;

      firebaseSubscription = _dbRef
          .child('wallets')
          .onValue
          .listen(
            (event) {
              final List<Wallet> visibleWallets = [];
              if (event.snapshot.exists) {
                final allWalletsMap =
                    event.snapshot.value as Map<dynamic, dynamic>;
                allWalletsMap.forEach((key, value) {
                  final walletSnapshot = event.snapshot.child(key);
                  final wallet = Wallet.fromSnapshot(walletSnapshot);

                  if (wallet.ownerId == _uid) {
                    visibleWallets.add(wallet);
                  } else if (wallet.ownerId == pId) {
                    visibleWallets.add(wallet);
                  } else if (wallet.ownerId == partnerUid &&
                      wallet.isVisibleToPartner) {
                    visibleWallets.add(wallet);
                  }
                });
              }
              controller.add(visibleWallets);
            },
            onError: (error) {
              print('❌ Firebase partnership wallet stream error: $error');
              if (!hasEmittedOfflineData) {
                _loadOfflineWallets(userProvider).then((offlineWallets) {
                  controller.add(offlineWallets);
                });
              }
            },
          );
    }

    controller.onCancel = () {
      firebaseSubscription?.cancel();
    };

    return controller.stream;
  }

  /// Helper method to load offline wallets
  Future<List<Wallet>> _loadOfflineWallets(UserProvider userProvider) async {
    try {
      if (userProvider.partnershipId != null) {
        // Load both personal and partnership wallets
        final personalWallets = await _syncService.getWallets(_uid!);
        final partnershipWallets = await _syncService.getWallets(
          userProvider.partnershipId!,
        );

        // Combine and deduplicate
        final allWallets = <String, Wallet>{};
        for (final wallet in personalWallets) {
          allWallets[wallet.id] = wallet;
        }
        for (final wallet in partnershipWallets) {
          allWallets[wallet.id] = wallet;
        }

        return allWallets.values.toList();
      } else {
        return await _syncService.getWallets(_uid!);
      }
    } catch (e) {
      print('❌ Error loading offline wallets: $e');
      return [];
    }
  }

  Stream<List<Wallet>> getSelectableWalletsStream(UserProvider userProvider) {
    if (_uid == null) return Stream.value([]);

    return _dbRef
        .child('wallets')
        .onValue
        .map((event) {
          final List<Wallet> selectableWallets = [];
          if (event.snapshot.exists) {
            final allWalletsMap = event.snapshot.value as Map<dynamic, dynamic>;
            allWalletsMap.forEach((key, value) {
              final walletSnapshot = event.snapshot.child(key);
              final wallet = Wallet.fromSnapshot(walletSnapshot);

              if (wallet.ownerId == _uid ||
                  wallet.ownerId == userProvider.partnershipId) {
                selectableWallets.add(wallet);
              }
            });
          }
          return selectableWallets;
        })
        .handleError((error) {
          print('❌ Selectable wallets stream error, falling back to offline');
          return _loadOfflineWallets(userProvider);
        });
  }

  // ============ ENHANCED CATEGORY METHODS ============

  Stream<List<Category>> getCategoriesByTypeStream(String type) {
    if (_uid == null) return Stream.value([]);

    final controller = StreamController<List<Category>>();
    bool hasEmittedOfflineData = false;

    // Load offline data first
    _syncService.getCategories(userId: _uid!, type: type).then((
      offlineCategories,
    ) {
      if (offlineCategories.isNotEmpty) {
        controller.add(offlineCategories);
        hasEmittedOfflineData = true;
      }
    });

    // Setup Firebase stream
    final categoryRef = _dbRef.child('categories').child(_uid!);
    final firebaseSubscription = categoryRef.onValue.listen(
      (event) {
        final List<Category> categories = [];
        if (event.snapshot.exists) {
          final map = event.snapshot.value as Map<dynamic, dynamic>;
          map.forEach((key, value) {
            final snapshot = event.snapshot.child(key);
            final category = Category.fromSnapshot(snapshot);
            if (category.type == type) {
              categories.add(category);
            }
          });
        }
        controller.add(categories);
      },
      onError: (error) {
        print('❌ Firebase category stream error: $error');
        if (!hasEmittedOfflineData) {
          _syncService.getCategories(userId: _uid!, type: type).then((
            offlineCategories,
          ) {
            controller.add(offlineCategories);
          });
        }
      },
    );

    controller.onCancel = () {
      firebaseSubscription?.cancel();
    };

    return controller.stream;
  }

  Stream<List<Category>> getCategoriesStream() {
    if (_uid == null) return Stream.value([]);

    final controller = StreamController<List<Category>>();
    bool hasEmittedOfflineData = false;

    // Load offline data first
    _syncService.getCategories(userId: _uid!).then((offlineCategories) {
      if (offlineCategories.isNotEmpty) {
        controller.add(offlineCategories);
        hasEmittedOfflineData = true;
      }
    });

    // Setup Firebase stream
    final categoryRef = _dbRef.child('categories').child(_uid!);
    final firebaseSubscription = categoryRef.onValue.listen(
      (event) {
        final List<Category> categories = [];
        if (event.snapshot.exists) {
          final map = event.snapshot.value as Map<dynamic, dynamic>;
          map.forEach((key, value) {
            final snapshot = event.snapshot.child(key);
            categories.add(Category.fromSnapshot(snapshot));
          });
        }
        controller.add(categories);
      },
      onError: (error) {
        print('❌ Firebase category stream error: $error');
        if (!hasEmittedOfflineData) {
          _syncService.getCategories(userId: _uid!).then((offlineCategories) {
            controller.add(offlineCategories);
          });
        }
      },
    );

    controller.onCancel = () {
      firebaseSubscription?.cancel();
    };

    return controller.stream;
  }

  // ============ ENHANCED TRANSACTION STREAMS ============

  Stream<List<TransactionModel>> getRecentTransactionsStream(
    UserProvider userProvider, {
    int limit = 15,
  }) {
    if (_uid == null) return Stream.value([]);

    final controller = StreamController<List<TransactionModel>>();
    bool hasEmittedOfflineData = false;

    // Load offline data first
    _loadOfflineTransactions(userProvider, limit: limit).then((
      offlineTransactions,
    ) {
      if (offlineTransactions.isNotEmpty) {
        controller.add(offlineTransactions);
        hasEmittedOfflineData = true;
      }
    });

    // Setup Firebase streams
    final walletsStream = getWalletsStream(userProvider);
    final categoriesStream = getCategoriesStream();

    final transRef = _dbRef
        .child('transactions')
        .orderByChild('userId')
        .equalTo(_uid)
        .limitToLast(limit);

    final recentTransStream = transRef.onValue
        .map((event) {
          final List<TransactionModel> transactions = [];
          if (event.snapshot.exists) {
            final map = event.snapshot.value as Map<dynamic, dynamic>;
            map.forEach((key, value) {
              final snapshot = event.snapshot.child(key);
              transactions.add(TransactionModel.fromSnapshot(snapshot));
            });
          }
          transactions.sort((a, b) => b.date.compareTo(a.date));
          return transactions;
        })
        .handleError((error) {
          print('❌ Firebase transaction stream error: $error');
          return <TransactionModel>[];
        });

    final combinedSubscription =
        StreamZip([walletsStream, categoriesStream, recentTransStream]).listen(
          (results) {
            final List<Wallet> wallets = results[0] as List<Wallet>;
            final List<Category> categories = results[1] as List<Category>;
            final List<TransactionModel> transactions =
                results[2] as List<TransactionModel>;

            final enrichedTransactions = _enrichTransactionsWithNames(
              transactions,
              wallets,
              categories,
            );

            controller.add(enrichedTransactions);
          },
          onError: (error) {
            print('❌ Combined stream error: $error');
            if (!hasEmittedOfflineData) {
              _loadOfflineTransactions(userProvider, limit: limit).then((
                offlineTransactions,
              ) {
                controller.add(offlineTransactions);
              });
            }
          },
        );

    controller.onCancel = () {
      combinedSubscription?.cancel();
    };

    return controller.stream;
  }

  /// Helper method to load offline transactions
  Future<List<TransactionModel>> _loadOfflineTransactions(
    UserProvider userProvider, {
    int? limit,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final transactions = await _syncService.getTransactions(
        userId: _uid!,
        startDate: startDate ?? DateTime(2020),
        endDate: endDate ?? DateTime.now().add(const Duration(days: 1)),
        limit: limit,
      );

      // Get offline wallets and categories to enrich data
      final wallets = await _loadOfflineWallets(userProvider);
      final categories = await _syncService.getCategories(userId: _uid!);

      return _enrichTransactionsWithNames(transactions, wallets, categories);
    } catch (e) {
      print('❌ Error loading offline transactions: $e');
      return [];
    }
  }

  /// Helper method to enrich transactions with wallet and category names
  List<TransactionModel> _enrichTransactionsWithNames(
    List<TransactionModel> transactions,
    List<Wallet> wallets,
    List<Category> categories,
  ) {
    final walletsMap = {for (var w in wallets) w.id: w};
    final categoriesMap = {for (var c in categories) c.id: c};

    return transactions.map((trans) {
      final wallet =
          walletsMap[trans.walletId] ??
          Wallet(id: '', name: 'Ví đã xóa', balance: 0, ownerId: '');

      String categoryName = 'Không có';
      String subCategoryName = '';

      if (trans.categoryId != null) {
        final category =
            categoriesMap[trans.categoryId] ??
            const Category(
              id: '',
              name: 'Danh mục đã xóa',
              ownerId: '',
              type: 'expense',
            );
        categoryName = category.name;

        if (trans.subCategoryId != null &&
            category.subCategories.containsKey(trans.subCategoryId)) {
          subCategoryName = category.subCategories[trans.subCategoryId]!;
        }
      }

      String transferFromWalletName = '';
      String transferToWalletName = '';

      if (trans.type == TransactionType.transfer &&
          trans.transferToWalletId != null) {
        final targetWallet =
            walletsMap[trans.transferToWalletId] ??
            Wallet(id: '', name: 'Ví đã xóa', balance: 0, ownerId: '');

        if (trans.description.contains('Chuyển đến:')) {
          transferFromWalletName = wallet.name;
          transferToWalletName = targetWallet.name;
        } else {
          transferFromWalletName = targetWallet.name;
          transferToWalletName = wallet.name;
        }
      }

      return trans.copyWith(
        walletName: wallet.name,
        categoryName: categoryName,
        subCategoryName: subCategoryName,
        transferFromWalletName: transferFromWalletName,
        transferToWalletName: transferToWalletName,
      );
    }).toList();
  }

  Stream<List<TransactionModel>> getTransactionsStream(
    UserProvider userProvider,
    DateTime startDate,
    DateTime endDate,
  ) {
    if (userProvider.currentUser == null) {
      return Stream.value([]);
    }

    final controller = StreamController<List<TransactionModel>>();
    bool hasEmittedOfflineData = false;

    // Load offline data first
    _loadOfflineTransactions(
      userProvider,
      startDate: startDate,
      endDate: endDate,
    ).then((offlineTransactions) {
      if (offlineTransactions.isNotEmpty) {
        controller.add(offlineTransactions);
        hasEmittedOfflineData = true;
      }
    });

    // Setup Firebase data fetching
    getWalletsStream(userProvider)
        .asyncMap((visibleWallets) async {
          final visibleWalletIds = visibleWallets.map((w) => w.id).toSet();
          if (visibleWalletIds.isEmpty) {
            return <TransactionModel>[];
          }

          try {
            final currentUserTransactionsSnapshot = await _dbRef
                .child('transactions')
                .orderByChild('userId')
                .equalTo(userProvider.currentUser!.uid)
                .get();

            DataSnapshot? partnerTransactionsSnapshot;
            if (userProvider.partnerUid != null) {
              partnerTransactionsSnapshot = await _dbRef
                  .child('transactions')
                  .orderByChild('userId')
                  .equalTo(userProvider.partnerUid)
                  .get();
            }

            final allTransactions = <TransactionModel>[];

            if (currentUserTransactionsSnapshot.exists) {
              (currentUserTransactionsSnapshot.value as Map).forEach((
                key,
                value,
              ) {
                allTransactions.add(
                  TransactionModel.fromSnapshot(
                    currentUserTransactionsSnapshot.child(key),
                  ),
                );
              });
            }

            if (partnerTransactionsSnapshot != null &&
                partnerTransactionsSnapshot.exists) {
              (partnerTransactionsSnapshot.value as Map).forEach((key, value) {
                allTransactions.add(
                  TransactionModel.fromSnapshot(
                    partnerTransactionsSnapshot!.child(key),
                  ),
                );
              });
            }

            final partnershipCreationDate =
                userProvider.partnershipCreationDate;

            final filteredTransactions = allTransactions.where((transaction) {
              final transactionDate = transaction.date;

              final isWalletVisible = visibleWalletIds.contains(
                transaction.walletId,
              );
              if (!isWalletVisible) return false;

              final isDateInRange =
                  transactionDate.isAfter(
                    startDate.subtract(const Duration(days: 1)),
                  ) &&
                  transactionDate.isBefore(
                    endDate.add(const Duration(days: 1)),
                  );
              if (!isDateInRange) return false;

              if (transaction.userId == userProvider.partnerUid) {
                return partnershipCreationDate != null &&
                    transactionDate.isAfter(partnershipCreationDate);
              }

              return true;
            }).toList();

            filteredTransactions.sort((a, b) => b.date.compareTo(a.date));

            // Enrich transactions
            final categories = await getCategoriesStream().first;
            return _enrichTransactionsWithNames(
              filteredTransactions,
              visibleWallets,
              categories,
            );
          } catch (e) {
            print('❌ Error fetching Firebase transactions: $e');
            return <TransactionModel>[];
          }
        })
        .listen(
          (transactions) {
            controller.add(transactions);
          },
          onError: (error) {
            print('❌ Transaction stream error: $error');
            if (!hasEmittedOfflineData) {
              _loadOfflineTransactions(
                userProvider,
                startDate: startDate,
                endDate: endDate,
              ).then((offlineTransactions) {
                controller.add(offlineTransactions);
              });
            }
          },
        );

    return controller.stream;
  }

  // ============ ENHANCED REPORT DATA METHODS ============

  Future<ReportData> getReportData(
    UserProvider userProvider,
    DateTime startDate,
    DateTime endDate,
  ) async {
    if (userProvider.currentUser == null) {
      throw Exception('Người dùng chưa đăng nhập');
    }

    try {
      // Try to get data from streams first, fallback to offline if needed
      final transactions =
          await getTransactionsStream(
            userProvider,
            startDate,
            endDate,
          ).first.timeout(
            const Duration(seconds: 10),
            onTimeout: () async {
              print('⚠️ Firebase timeout, using offline data');
              return await _loadOfflineTransactions(
                userProvider,
                startDate: startDate,
                endDate: endDate,
              );
            },
          );

      final categories = await getCategoriesStream().first.timeout(
        const Duration(seconds: 5),
        onTimeout: () async {
          print('⚠️ Categories timeout, using offline data');
          return await _syncService.getCategories(userId: _uid!);
        },
      );

      final wallets = await getWalletsStream(userProvider).first.timeout(
        const Duration(seconds: 5),
        onTimeout: () async {
          print('⚠️ Wallets timeout, using offline data');
          return await _loadOfflineWallets(userProvider);
        },
      );

      return _processReportData(
        transactions,
        categories,
        wallets,
        userProvider,
      );
    } catch (e) {
      print('❌ Error getting report data, falling back to offline: $e');

      // Complete offline fallback
      final offlineTransactions = await _loadOfflineTransactions(
        userProvider,
        startDate: startDate,
        endDate: endDate,
      );

      final offlineCategories = await _syncService.getCategories(userId: _uid!);
      final offlineWallets = await _loadOfflineWallets(userProvider);

      return _processReportData(
        offlineTransactions,
        offlineCategories,
        offlineWallets,
        userProvider,
      );
    }
  }

  /// Helper method to process report data
  ReportData _processReportData(
    List<TransactionModel> transactions,
    List<Category> categories,
    List<Wallet> wallets,
    UserProvider userProvider,
  ) {
    double personalIncome = 0;
    double personalExpense = 0;
    double sharedIncome = 0;
    double sharedExpense = 0;
    Map<Category, double> expenseByCategory = {};
    Map<Category, double> incomeByCategory = {};

    final walletOwnerMap = {for (var w in wallets) w.id: w.ownerId};

    for (final transaction in transactions) {
      final ownerId = walletOwnerMap[transaction.walletId];
      final bool isShared = ownerId == userProvider.partnershipId;

      if (transaction.type == TransactionType.income) {
        if (isShared) {
          sharedIncome += transaction.amount;
        } else {
          personalIncome += transaction.amount;
        }

        if (transaction.categoryId != null) {
          final category = categories.firstWhere(
            (c) => c.id == transaction.categoryId,
            orElse: () => Category(
              id: 'unknown_income',
              name: 'Chưa phân loại',
              ownerId: '',
              type: 'income',
            ),
          );
          incomeByCategory.update(
            category,
            (v) => v + transaction.amount,
            ifAbsent: () => transaction.amount,
          );
        }
      } else if (transaction.type == TransactionType.expense) {
        if (isShared) {
          sharedExpense += transaction.amount;
        } else {
          personalExpense += transaction.amount;
        }

        if (transaction.categoryId != null) {
          final category = categories.firstWhere(
            (c) => c.id == transaction.categoryId,
            orElse: () => Category(
              id: 'unknown_expense',
              name: 'Chưa phân loại',
              ownerId: '',
              type: 'expense',
            ),
          );
          expenseByCategory.update(
            category,
            (v) => v + transaction.amount,
            ifAbsent: () => transaction.amount,
          );
        }
      }
    }

    return ReportData(
      totalIncome: personalIncome + sharedIncome,
      totalExpense: personalExpense + sharedExpense,
      personalIncome: personalIncome,
      personalExpense: personalExpense,
      sharedIncome: sharedIncome,
      sharedExpense: sharedExpense,
      expenseByCategory: expenseByCategory,
      incomeByCategory: incomeByCategory,
      rawTransactions: transactions,
    );
  }

  // ============ ENHANCED DESCRIPTION METHODS ============

  Future<List<String>> getDescriptionHistory() async {
    if (_uid == null) return [];

    try {
      // Get from offline sync service (enhanced with context)
      final suggestions = await _syncService.getDescriptionSuggestions(_uid!);

      if (suggestions.isNotEmpty) {
        return suggestions;
      }

      // Fallback to Firebase
      final snapshot = await _dbRef
          .child('user_descriptions')
          .child(_uid!)
          .get();

      if (snapshot.exists) {
        final descriptionsMap = snapshot.value as Map<dynamic, dynamic>;
        final firebaseDescriptions = descriptionsMap.keys
            .cast<String>()
            .toList();

        // Cache Firebase descriptions to local DB
        for (final desc in firebaseDescriptions) {
          await _syncService.saveDescriptionWithContext(_uid!, desc);
        }

        return firebaseDescriptions;
      }

      return [];
    } catch (e) {
      print("❌ Error getting description history: $e");
      return [];
    }
  }

  Future<void> saveDescriptionToHistory(String description) async {
    if (_uid == null || description.isEmpty) return;

    try {
      // Use sync service for enhanced saving with context
      await _syncService.saveDescriptionWithContext(_uid!, description);
    } catch (e) {
      print("⚠️ Warning: Failed to save description: $e");
    }
  }

  Future<List<String>> searchDescriptionHistory(
    String query, {
    int limit = 5,
  }) async {
    if (_uid == null || query.trim().isEmpty) return [];

    try {
      return await _syncService.searchDescriptionHistory(
        _uid!,
        query.trim(),
        limit: limit,
      );
    } catch (e) {
      print("❌ Error searching description history: $e");
      return [];
    }
  }

  // ============ LEGACY ONLINE-ONLY METHODS (FOR BACKWARD COMPATIBILITY) ============

  Future<void> addWallet(
    String name,
    double initialBalance,
    String ownerId,
  ) async {
    if (_uid == null) return;

    try {
      final newWalletRef = _dbRef.child('wallets').push();
      final newWallet = Wallet(
        id: newWalletRef.key!,
        name: name,
        balance: initialBalance,
        ownerId: ownerId,
        isVisibleToPartner: true,
      );

      await newWalletRef.set(newWallet.toJson());
      await _localDb.saveWalletLocally(newWallet, syncStatus: 1);
    } catch (e) {
      print("❌ Error adding wallet online: $e");
      // Fallback to offline
      await addWalletOffline(name, initialBalance, ownerId);
    }
  }

  Future<void> addCategory(String name, String type) async {
    if (_uid == null) return;

    try {
      final newCategoryRef = _dbRef.child('categories').child(_uid!).push();
      final newCategory = Category(
        id: newCategoryRef.key!,
        name: name,
        ownerId: _uid!,
        type: type,
      );

      await newCategoryRef.set(newCategory.toJson());
      await _localDb.saveCategoryLocally(newCategory, syncStatus: 1);
    } catch (e) {
      print("❌ Error adding category online: $e");
      // Fallback to offline
      await addCategoryOffline(name, type);
    }
  }

  Future<void> updateTransaction(
    TransactionModel newTransaction,
    TransactionModel oldTransaction,
  ) async {
    if (_uid == null) return;

    try {
      // Update Firebase
      await _dbRef
          .child('transactions')
          .child(newTransaction.id)
          .set(newTransaction.toJson());

      // Update wallet balance
      await _updateWalletBalanceForTransaction(newTransaction, oldTransaction);

      // Update local database
      await _localDb.saveTransactionLocally(newTransaction, syncStatus: 1);

      // Save description
      if (newTransaction.description.isNotEmpty) {
        await saveDescriptionToHistory(newTransaction.description);
      }
    } catch (e) {
      print("❌ Error updating transaction: $e");
      rethrow;
    }
  }

  Future<void> _updateWalletBalanceForTransaction(
    TransactionModel newTransaction,
    TransactionModel oldTransaction,
  ) async {
    try {
      final newWalletRef = _dbRef
          .child('wallets')
          .child(newTransaction.walletId);
      final oldWalletRef = _dbRef
          .child('wallets')
          .child(oldTransaction.walletId);

      double getBalanceChange(TransactionModel trans) {
        switch (trans.type) {
          case TransactionType.income:
            return trans.amount;
          case TransactionType.expense:
            return -trans.amount;
          case TransactionType.transfer:
            return -trans.amount;
        }
      }

      if (newTransaction.walletId == oldTransaction.walletId) {
        final oldChange = getBalanceChange(oldTransaction);
        final newChange = getBalanceChange(newTransaction);
        final difference = newChange - oldChange;

        await newWalletRef
            .child('balance')
            .set(ServerValue.increment(difference));
      } else {
        final oldReversal = -getBalanceChange(oldTransaction);
        final newChange = getBalanceChange(newTransaction);

        await oldWalletRef
            .child('balance')
            .set(ServerValue.increment(oldReversal));
        await newWalletRef
            .child('balance')
            .set(ServerValue.increment(newChange));
      }
    } catch (e) {
      print("⚠️ Failed to update wallet balance: $e");
    }
  }

  Future<void> deleteTransaction(TransactionModel transaction) async {
    if (_uid == null) return;

    try {
      // Delete from Firebase
      await _dbRef.child('transactions').child(transaction.id).remove();

      // Reverse wallet balance changes
      final walletRef = _dbRef.child('wallets').child(transaction.walletId);

      double reversalAmount = 0;
      switch (transaction.type) {
        case TransactionType.income:
          reversalAmount = -transaction.amount;
          break;
        case TransactionType.expense:
          reversalAmount = transaction.amount;
          break;
        case TransactionType.transfer:
          reversalAmount = transaction.amount;
          break;
      }

      await walletRef
          .child('balance')
          .set(ServerValue.increment(reversalAmount));

      // Remove from local database
      final db = await _localDb.database;
      await db.delete(
        'transactions',
        where: 'id = ?',
        whereArgs: [transaction.id],
      );
    } catch (e) {
      print("❌ Error deleting transaction: $e");
      rethrow;
    }
  }

  Future<void> addTransferTransaction({
    required String fromWalletId,
    required String toWalletId,
    required double amount,
    String? description,
    required String fromWalletName,
    required String toWalletName,
  }) async {
    if (_uid == null) return;

    final userId = _uid!;
    final date = DateTime.now();

    final finalDescription = description != null && description.isNotEmpty
        ? description
        : 'Chuyển tiền';

    try {
      // Create transfer transaction
      final fromTrans = TransactionModel(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        amount: amount,
        type: TransactionType.transfer,
        walletId: fromWalletId,
        date: date,
        description: 'Chuyển đến: $toWalletName',
        userId: userId,
        transferToWalletId: toWalletId,
      );

      // Add transaction (will use offline-first approach)
      await addTransaction(fromTrans);

      // Update wallet balances directly (for immediate effect)
      try {
        final fromWalletRef = _dbRef.child('wallets').child(fromWalletId);
        final toWalletRef = _dbRef.child('wallets').child(toWalletId);

        await fromWalletRef
            .child('balance')
            .set(ServerValue.increment(-amount));
        await toWalletRef.child('balance').set(ServerValue.increment(amount));
      } catch (e) {
        print('⚠️ Warning: Could not update wallet balances immediately: $e');
      }
    } catch (e) {
      print("❌ Error adding transfer transaction: $e");
      rethrow;
    }
  }

  // ============ OTHER METHODS (KEEP EXISTING FUNCTIONALITY) ============

  Stream<Budget?> getBudgetForMonthStream(String month) {
    if (_uid == null) return Stream.value(null);

    final budgetRef = _dbRef
        .child('budgets')
        .orderByChild('ownerId_month')
        .equalTo('${_uid}_$month');

    return budgetRef.onValue.map((event) {
      if (event.snapshot.exists && event.snapshot.children.isNotEmpty) {
        return Budget.fromSnapshot(event.snapshot.children.first);
      }
      return null;
    });
  }

  Future<void> saveBudget(Budget budget) async {
    if (_uid == null) return;

    DatabaseReference ref;
    if (budget.id.isNotEmpty) {
      ref = _dbRef.child('budgets').child(budget.id);
    } else {
      ref = _dbRef.child('budgets').push();
    }

    final dataToSet = budget.toJson()
      ..['ownerId_month'] = '${budget.ownerId}_${budget.month}';

    await ref.set(dataToSet);
  }

  Future<void> updateWalletVisibility(String walletId, bool isVisible) async {
    try {
      await _dbRef
          .child('wallets')
          .child(walletId)
          .child('isVisibleToPartner')
          .set(isVisible);
    } catch (e) {
      print("❌ Error updating wallet visibility: $e");
      rethrow;
    }
  }

  Future<void> setCategoryBudget(
    String budgetId,
    String categoryId,
    double amount,
  ) async {
    try {
      await _dbRef
          .child('budgets')
          .child(budgetId)
          .child('categoryAmounts')
          .child(categoryId)
          .set(amount);
    } catch (e) {
      print("❌ Error setting category budget: $e");
      rethrow;
    }
  }

  Future<void> addSubCategory(
    String parentCategoryId,
    String subCategoryName,
  ) async {
    if (_uid == null) return;
    try {
      final subCategoryRef = _dbRef
          .child('categories')
          .child(_uid!)
          .child(parentCategoryId)
          .child('subCategories')
          .push();

      await subCategoryRef.set(subCategoryName);
    } catch (e) {
      print("❌ Error adding sub category: $e");
      rethrow;
    }
  }

  Future<void> deleteSubCategory(
    String parentCategoryId,
    String subCategoryId,
  ) async {
    if (_uid == null) return;
    try {
      await _dbRef
          .child('categories')
          .child(_uid!)
          .child(parentCategoryId)
          .child('subCategories')
          .child(subCategoryId)
          .remove();
    } catch (e) {
      print("❌ Error deleting sub category: $e");
      rethrow;
    }
  }

  // ============ PARTNERSHIP METHODS ============

  Stream<List<TransactionModel>> getTransactionsForCategoryStream({
    required UserProvider userProvider,
    required String categoryId,
    required DateTime startDate,
    required DateTime endDate,
  }) async* {
    await for (final allTransactions in getTransactionsStream(
      userProvider,
      startDate,
      endDate,
    )) {
      yield allTransactions
          .where((trans) => trans.categoryId == categoryId)
          .toList();
    }
  }

  Map<String, double> groupTransactionsByMonth(
    List<TransactionModel> transactions,
  ) {
    final DateFormat formatter = DateFormat('MMM yyyy', 'vi_VN');

    final groupedByMonth = groupBy(transactions, (TransactionModel t) {
      return formatter.format(t.date);
    });

    return groupedByMonth.map((month, transList) {
      final total = transList.fold(0.0, (sum, item) => sum + item.amount);
      return MapEntry(month, total);
    });
  }

  Future<String?> getPartnershipId(String uid) async {
    final ref = _dbRef.child('users').child(uid).child('partnershipId');
    final snapshot = await ref.get();
    if (snapshot.exists) {
      return snapshot.value as String?;
    }
    return null;
  }

  Future<void> leavePartnership(String partnershipId) async {
    if (_uid == null) return;

    final partnershipRef = _dbRef.child('partnerships').child(partnershipId);
    final userRef = _dbRef.child('users').child(_uid!);

    await userRef.update({
      'partnershipId': null,
      'partnerUid': null,
      'partnerDisplayName': null,
      'partnershipCreatedAt': null,
    });

    final partnershipSnapshot = await partnershipRef.get();
    if (partnershipSnapshot.exists) {
      final members = (partnershipSnapshot.value as Map)['memberIds'] as List;
      if (members.length <= 1) {
        await partnershipRef.remove();
      } else {
        members.remove(_uid);
        await partnershipRef.update({'memberIds': members});
      }
    }
  }

  Future<void> handlePartnershipInvite(String inviteCode) async {
    if (_uid == null) throw Exception('User not authenticated');

    try {
      final inviteSnapshot = await _dbRef
          .child('inviteCodes')
          .child(inviteCode.toUpperCase())
          .get();

      if (!inviteSnapshot.exists) {
        throw Exception('Mã mời không hợp lệ hoặc đã hết hạn');
      }

      final inviteData = inviteSnapshot.value as Map<dynamic, dynamic>;
      final partnerUid = inviteData['userId'] as String;

      if (partnerUid == _uid) {
        throw Exception('Bạn không thể mời chính mình');
      }

      // Check existing partnerships
      final currentUserSnapshot = await _dbRef
          .child('users')
          .child(_uid!)
          .get();
      final partnerSnapshot = await _dbRef
          .child('users')
          .child(partnerUid)
          .get();

      if (currentUserSnapshot.exists) {
        final userData = currentUserSnapshot.value as Map<dynamic, dynamic>;
        if (userData['partnershipId'] != null) {
          throw Exception('Bạn đã có đối tác');
        }
      }

      if (partnerSnapshot.exists) {
        final partnerData = partnerSnapshot.value as Map<dynamic, dynamic>;
        if (partnerData['partnershipId'] != null) {
          throw Exception('Người này đã có đối tác');
        }
      }

      // Create partnership
      final newPartnershipRef = _dbRef.child('partnerships').push();
      final partnershipId = newPartnershipRef.key!;

      final currentUserData =
          currentUserSnapshot.value as Map<dynamic, dynamic>? ?? {};
      final partnerData = partnerSnapshot.value as Map<dynamic, dynamic>? ?? {};

      final partnership = {
        'members': {_uid: true, partnerUid: true},
        'memberNames': {
          _uid: currentUserData['displayName'] ?? 'User',
          partnerUid: partnerData['displayName'] ?? 'Partner',
        },
        'createdAt': ServerValue.timestamp,
        'isActive': true,
        'lastSyncTime': ServerValue.timestamp,
      };

      await _dbRef.child('partnerships').child(partnershipId).set(partnership);

      await _dbRef.child('users').child(_uid).update({
        'partnershipId': partnershipId,
        'partnerUid': partnerUid,
        'partnerDisplayName': partnerData['displayName'],
        'partnershipCreatedAt': ServerValue.timestamp,
      });

      await _dbRef.child('users').child(partnerUid).update({
        'partnershipId': partnershipId,
        'partnerUid': _uid,
        'partnerDisplayName': currentUserData['displayName'],
        'partnershipCreatedAt': ServerValue.timestamp,
      });

      await Future.wait([
        _sendNotification(
          _uid!,
          'Kết nối thành công!',
          'Bạn đã kết nối với ${partnerData['displayName'] ?? 'đối tác'}',
        ),
        _sendNotification(
          partnerUid,
          'Có người kết nối!',
          '${currentUserData['displayName'] ?? 'Ai đó'} đã chấp nhận lời mời',
        ),
      ]);

      await _dbRef
          .child('inviteCodes')
          .child(inviteCode.toUpperCase())
          .remove();
    } catch (e) {
      print('❌ Error handling partnership invite: $e');
      rethrow;
    }
  }

  Future<void> _sendNotification(
    String userId,
    String title,
    String body,
  ) async {
    try {
      await _dbRef.child('user_notifications').child(userId).push().set({
        'title': title,
        'body': body,
        'timestamp': ServerValue.timestamp,
        'type': 'partnership',
        'isRead': false,
      });
    } catch (e) {
      print('❌ Error sending notification: $e');
    }
  }

  Future<void> syncPartnership(String partnershipId) async {
    if (_uid == null) return;

    try {
      final partnershipRef = _dbRef.child('partnerships').child(partnershipId);
      final partnershipSnapshot = await partnershipRef.get();

      if (!partnershipSnapshot.exists) {
        await _dbRef.child('users').child(_uid!).update({
          'partnershipId': null,
          'partnerUid': null,
          'partnerDisplayName': null,
          'partnershipCreatedAt': null,
        });
        throw Exception('Partnership không tồn tại');
      }

      await partnershipRef.update({
        'lastSyncTime': ServerValue.timestamp,
        'isActive': true,
      });

      await _dbRef.child('users').child(_uid!).update({
        'lastSync': ServerValue.timestamp,
      });
    } catch (e) {
      print('❌ Error syncing partnership: $e');
      rethrow;
    }
  }

  // ============ ENHANCED OFFLINE METHODS ============

  Future<List<TransactionModel>> getTransactionsOfflineFirst({
    String? userId,
    DateTime? startDate,
    DateTime? endDate,
    int? limit,
  }) async {
    try {
      final localTransactions = await _syncService.getTransactions(
        userId: userId ?? _uid!,
        startDate: startDate ?? DateTime(2020),
        endDate: endDate ?? DateTime.now(),
        limit: limit,
      );

      if (localTransactions.isNotEmpty) {
        print(
          '📱 Returning ${localTransactions.length} transactions from local DB',
        );
        return localTransactions;
      }

      print('☁️ No local transactions, would need to fetch from Firebase...');
      return [];
    } catch (e) {
      print('❌ Error getting transactions offline-first: $e');
      return [];
    }
  }

  Future<void> syncLocalChangesToFirebase() async {
    if (_uid == null) return;

    try {
      // Force sync through the sync service
      await _syncService.forceSyncNow();
      print('🎉 Local changes synced to Firebase successfully');
    } catch (e) {
      print('❌ Error syncing local changes: $e');
    }
  }

  Future<Map<String, dynamic>> getDatabaseHealth() async {
    try {
      final localStats = await _localDb.getDatabaseStats();
      final syncStats = _syncService.getSyncStats();

      // Test Firebase connection
      bool firebaseConnected = false;
      try {
        await _dbRef.child('.info/connected').get();
        firebaseConnected = true;
      } catch (e) {
        firebaseConnected = false;
      }

      return {
        'localDatabase': localStats,
        'syncService': syncStats,
        'firebaseConnected': firebaseConnected,
        'lastHealthCheck': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      return {
        'error': e.toString(),
        'firebaseConnected': false,
        'lastHealthCheck': DateTime.now().toIso8601String(),
      };
    }
  }

  // ============ CONNECTIVITY MANAGEMENT ============

  Future<void> syncWhenOnline() async {
    final connectivity = Connectivity();
    connectivity.onConnectivityChanged.listen(
      (ConnectivityResult result) {
            if (result != ConnectivityResult.none) {
              _performSync();
            }
          }
          as void Function(List<ConnectivityResult> event)?,
    );
  }

  Future<void> _performSync() async {
    try {
      await _syncService.forceSyncNow();
      print('✅ Connectivity sync completed successfully');
    } catch (e) {
      print('❌ Connectivity sync failed: $e');
    }
  }

  // ============ ERROR HANDLING ============

  void handleError(dynamic error, {String? context}) {
    final errorMessage = context != null
        ? '$context: $error'
        : 'Database error: $error';
    print('🚨 $errorMessage');
  }
}
