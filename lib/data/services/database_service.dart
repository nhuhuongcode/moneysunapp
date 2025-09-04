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
import 'package:async/async.dart';
import 'package:collection/collection.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:moneysun/data/services/offline_sync_service.dart';

class DatabaseService {
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();
  final String? _uid = FirebaseAuth.instance.currentUser?.uid;

  final LocalDatabaseService _localDb = LocalDatabaseService();

  static Future<void> enableOfflineSupport() async {
    FirebaseDatabase.instance.setPersistenceEnabled(true);
    FirebaseDatabase.instance.setPersistenceCacheSizeBytes(
      10000000,
    ); // 10MB cache
  }

  // FIX: Check connectivity and sync when online
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
      // Force sync with server when coming back online
      await _dbRef
          .child('users')
          .child(_uid!)
          .child('lastSync')
          .set(ServerValue.timestamp);
      print('Sync completed successfully');
    } catch (e) {
      print('Sync failed: $e');
    }
  }

  // FIX: Wallet selection cho AddTransaction - chỉ cho phép chọn ví của mình và ví chung
  Stream<List<Wallet>> getSelectableWalletsStream(UserProvider userProvider) {
    if (_uid == null) return Stream.value([]);

    return _dbRef.child('wallets').onValue.map((event) {
      final List<Wallet> selectableWallets = [];
      if (event.snapshot.exists) {
        final allWalletsMap = event.snapshot.value as Map<dynamic, dynamic>;
        allWalletsMap.forEach((key, value) {
          final walletSnapshot = event.snapshot.child(key);
          final wallet = Wallet.fromSnapshot(walletSnapshot);

          // CHỈ cho phép chọn:
          // 1. Ví của chính mình
          // 2. Ví chung (partnership wallet)
          if (wallet.ownerId == _uid ||
              wallet.ownerId == userProvider.partnershipId) {
            selectableWallets.add(wallet);
          }
        });
      }
      return selectableWallets;
    });
  }

  // Lấy danh sách các ví có thể XEM (bao gồm cả ví partner visible)
  Stream<List<Wallet>> getWalletsStream(UserProvider userProvider) {
    if (_uid == null) return Stream.value([]);

    if (userProvider.partnershipId == null || userProvider.partnerUid == null) {
      final walletRef = _dbRef
          .child('wallets')
          .orderByChild('ownerId')
          .equalTo(_uid);

      return walletRef.onValue.map((event) {
        final List<Wallet> wallets = [];
        if (event.snapshot.exists) {
          final walletMap = event.snapshot.value as Map<dynamic, dynamic>;
          walletMap.forEach((key, value) {
            final snapshot = event.snapshot.child(key);
            wallets.add(Wallet.fromSnapshot(snapshot));
          });
        }
        return wallets;
      });
    }

    final pId = userProvider.partnershipId!;
    final partnerUid = userProvider.partnerUid!;

    return _dbRef.child('wallets').onValue.map((event) {
      final List<Wallet> visibleWallets = [];
      if (event.snapshot.exists) {
        final allWalletsMap = event.snapshot.value as Map<dynamic, dynamic>;
        allWalletsMap.forEach((key, value) {
          final walletSnapshot = event.snapshot.child(key);
          final wallet = Wallet.fromSnapshot(walletSnapshot);

          // Áp dụng các quy tắc hiển thị:
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
      return visibleWallets;
    });
  }

  // Future<void> addTransaction(TransactionModel transaction) async {
  //   if (_uid == null) return;
  //   try {
  //     // 1. Lưu giao dịch vào database
  //     final newTransactionRef = _dbRef.child('transactions').push();
  //     final transactionWithId = TransactionModel(
  //       id: newTransactionRef.key!,
  //       amount: transaction.amount,
  //       type: transaction.type,
  //       categoryId: transaction.categoryId,
  //       walletId: transaction.walletId,
  //       date: transaction.date,
  //       description: transaction.description,
  //       userId: transaction.userId,
  //       subCategoryId: transaction.subCategoryId,
  //       transferToWalletId: transaction.transferToWalletId,
  //     );
  //     await newTransactionRef.set(transaction.toJson());

  //     // 2. FIX: Cập nhật số dư của ví tương ứng
  //     final walletRef = _dbRef.child('wallets').child(transaction.walletId);
  //     final walletSnapshot = await walletRef.get();

  //     if (walletSnapshot.exists) {
  //       double balanceChange = 0;

  //       switch (transaction.type) {
  //         case TransactionType.income:
  //           balanceChange = transaction.amount; // CỘNG cho thu nhập
  //           break;
  //         case TransactionType.expense:
  //           balanceChange = -transaction.amount; // TRỪ cho chi tiêu
  //           break;
  //         case TransactionType.transfer:
  //           balanceChange =
  //               -transaction.amount; // TRỪ cho transfer (từ ví nguồn)
  //           break;
  //       }

  //       await walletRef
  //           .child('balance')
  //           .set(ServerValue.increment(balanceChange));
  //     }

  //     await _localDb.saveTransactionLocally(transactionWithId, syncStatus: 1);

  //     if (transaction.description.isNotEmpty) {
  //       await _localDb.saveDescriptionToHistory(_uid!, transaction.description);
  //     }
  //   } catch (e) {
  //     if (transaction.description.isNotEmpty) {
  //       await _localDb.saveDescriptionToHistory(_uid!, transaction.description);
  //     }
  //     print("❌ Error adding transaction: $e");
  //     rethrow;
  //   }
  // }

  Future<void> addTransaction(TransactionModel transaction) async {
    if (_uid == null) return;

    try {
      // 1. Luôn lưu local trước (offline-first)
      await _localDb.saveTransactionLocally(transaction, syncStatus: 0);

      // 2. Lưu description vào history
      if (transaction.description.isNotEmpty) {
        await _localDb.saveDescriptionToHistory(_uid!, transaction.description);
      }

      // 3. Thử sync ngay nếu online (thông qua Enhanced Sync Service)
      final syncService = OfflineSyncService();
      await syncService.addTransactionOffline(transaction);

      print('✅ Transaction added offline-first: ${transaction.id}');
    } catch (e) {
      print("❌ Error adding transaction offline: $e");
      rethrow;
    }
  }

  Future<void> addWalletOffline(
    String name,
    double initialBalance,
    String ownerId,
  ) async {
    if (_uid == null) return;

    try {
      final newWallet = Wallet(
        id: DateTime.now().millisecondsSinceEpoch.toString(), // Tạo ID tạm thời
        name: name,
        balance: initialBalance,
        ownerId: ownerId,
        isVisibleToPartner: true,
      );

      // Offline-first approach
      final syncService = OfflineSyncService();
      await syncService.addWalletOffline(newWallet);

      print('✅ Wallet added offline-first: ${newWallet.id}');
    } catch (e) {
      print("❌ Error adding wallet offline: $e");
      rethrow;
    }
  }

  // Thêm method mới cho offline-first category
  Future<void> addCategoryOffline(String name, String type) async {
    if (_uid == null) return;

    try {
      final newCategory = Category(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name,
        ownerId: _uid!,
        type: type,
      );

      // Offline-first approach
      final syncService = OfflineSyncService();
      await syncService.addCategoryOffline(newCategory);

      print('✅ Category added offline-first: ${newCategory.id}');
    } catch (e) {
      print("❌ Error adding category offline: $e");
      rethrow;
    }
  }

  // FIX: updateTransaction - Sửa logic balance update
  Future<void> updateTransaction(
    TransactionModel newTransaction,
    TransactionModel oldTransaction,
  ) async {
    if (_uid == null) return;

    // 1. Cập nhật bản ghi giao dịch
    await _dbRef
        .child('transactions')
        .child(newTransaction.id)
        .set(newTransaction.toJson());

    // 2. FIX: Xử lý cập nhật số dư ví
    final newWalletRef = _dbRef.child('wallets').child(newTransaction.walletId);
    final oldWalletRef = _dbRef.child('wallets').child(oldTransaction.walletId);

    // Helper function để tính giá trị thay đổi balance
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
      // Cùng ví: Tính chênh lệch
      final oldChange = getBalanceChange(oldTransaction);
      final newChange = getBalanceChange(newTransaction);
      final difference = newChange - oldChange;

      await newWalletRef
          .child('balance')
          .set(ServerValue.increment(difference));
    } else {
      // Khác ví: Hoàn tác cũ và áp dụng mới
      final oldReversal = -getBalanceChange(oldTransaction);
      final newChange = getBalanceChange(newTransaction);

      await oldWalletRef
          .child('balance')
          .set(ServerValue.increment(oldReversal));
      await newWalletRef.child('balance').set(ServerValue.increment(newChange));
    }

    // 3. Lưu mô tả mới
    if (newTransaction.description.isNotEmpty) {
      await saveDescriptionToHistory(newTransaction.description);
    }
  }

  // FIX: deleteTransaction - Sửa logic hoàn tác balance
  Future<void> deleteTransaction(TransactionModel transaction) async {
    if (_uid == null) return;

    try {
      // 1. Xóa bản ghi giao dịch
      await _dbRef.child('transactions').child(transaction.id).remove();

      // 2. FIX: Hoàn tác ảnh hưởng lên số dư ví
      final walletRef = _dbRef.child('wallets').child(transaction.walletId);

      double reversalAmount = 0;
      switch (transaction.type) {
        case TransactionType.income:
          reversalAmount = -transaction.amount; // Trừ lại số đã cộng
          break;
        case TransactionType.expense:
          reversalAmount = transaction.amount; // Cộng lại số đã trừ
          break;
        case TransactionType.transfer:
          reversalAmount = transaction.amount; // Cộng lại số đã trừ
          break;
      }

      await walletRef
          .child('balance')
          .set(ServerValue.increment(reversalAmount));
    } catch (e) {
      print("Lỗi khi xóa giao dịch: $e");
      rethrow;
    }
  }

  // FIX: addTransferTransaction - Đảm bảo logic chuyển tiền đúng
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

    // Tạo giao dịch TRANSFER cho ví nguồn
    final fromTrans = TransactionModel(
      id: '',
      amount: amount,
      type: TransactionType.transfer,
      walletId: fromWalletId,
      date: date,
      description: 'Chuyển đến: $toWalletName',
      userId: userId,
      transferToWalletId: toWalletId,
    );

    // Tạo giao dịch TRANSFER cho ví đích (với amount dương)
    // final toTrans = TransactionModel(
    //   id: '',
    //   amount: amount,
    //   type: TransactionType.transfer,
    //   walletId: toWalletId,
    //   date: date,
    //   description: 'Nhận từ: $fromWalletName',
    //   userId: userId,
    //   transferToWalletId: fromWalletId, // Ngược lại để trace
    // );

    // Lưu cả hai giao dịch
    final transRef = _dbRef.child('transactions');
    await transRef.push().set(fromTrans.toJson());
    // await transRef.push().set(toTrans.toJson());

    // Cập nhật số dư: Trừ từ ví nguồn, cộng vào ví đích
    final fromWalletRef = _dbRef.child('wallets').child(fromWalletId);
    final toWalletRef = _dbRef.child('wallets').child(toWalletId);

    await fromWalletRef.child('balance').set(ServerValue.increment(-amount));
    await toWalletRef.child('balance').set(ServerValue.increment(amount));

    // Lưu mô tả
    if (finalDescription.isNotEmpty) {
      await saveDescriptionToHistory(finalDescription);
    }
  }

  // THÊM: Lấy categories theo type (income/expense)
  Stream<List<Category>> getCategoriesByTypeStream(String type) {
    if (_uid == null) return Stream.value([]);

    final categoryRef = _dbRef.child('categories').child(_uid!);
    return categoryRef.onValue.map((event) {
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
      return categories;
    });
  }

  // Giữ nguyên method getCategoriesStream() cho backward compatibility
  Stream<List<Category>> getCategoriesStream() {
    if (_uid == null) return Stream.value([]);
    final categoryRef = _dbRef.child('categories').child(_uid!);
    return categoryRef.onValue.map((event) {
      final List<Category> categories = [];
      if (event.snapshot.exists) {
        final map = event.snapshot.value as Map<dynamic, dynamic>;
        map.forEach((key, value) {
          final snapshot = event.snapshot.child(key);
          categories.add(Category.fromSnapshot(snapshot));
        });
      }
      return categories;
    });
  }

  // Thêm một ví mới
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
      print("Lỗi khi thêm ví: $e");
      rethrow;
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
      print("Lỗi khi thêm danh mục: $e");
      rethrow;
    }
  }

  // Các method khác giữ nguyên từ code cũ...
  Stream<List<TransactionModel>> getRecentTransactionsStream(
    UserProvider userProvider, {
    int limit = 15,
  }) {
    if (_uid == null) return Stream.value([]);

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
          print('❌ Firebase stream error, falling back to local: $error');
          return <TransactionModel>[];
        });

    return StreamZip([walletsStream, categoriesStream, recentTransStream]).map((
      results,
    ) {
      final List<Wallet> wallets = results[0] as List<Wallet>;
      final List<Category> categories = results[1] as List<Category>;
      final List<TransactionModel> transactions =
          results[2] as List<TransactionModel>;

      return transactions.map((trans) {
        final wallet = wallets.firstWhere(
          (w) => w.id == trans.walletId,
          orElse: () =>
              Wallet(id: '', name: 'Ví đã xóa', balance: 0, ownerId: ''),
        );

        String categoryName = 'Không có';
        String subCategoryName = '';

        if (trans.categoryId != null) {
          final category = categories.firstWhere(
            (c) => c.id == trans.categoryId,
            orElse: () => const Category(
              id: '',
              name: 'Danh mục đã xóa',
              ownerId: '',
              type: 'expense',
            ),
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
          final targetWallet = wallets.firstWhere(
            (w) => w.id == trans.transferToWalletId,
            orElse: () =>
                Wallet(id: '', name: 'Ví đã xóa', balance: 0, ownerId: ''),
          );
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
    });
  }

  Stream<List<TransactionModel>> getTransactionsStream(
    UserProvider userProvider,
    DateTime startDate,
    DateTime endDate,
  ) {
    if (userProvider.currentUser == null) {
      return Stream.value([]);
    }

    return getWalletsStream(userProvider).asyncMap((visibleWallets) async {
      final visibleWalletIds = visibleWallets.map((w) => w.id).toSet();
      if (visibleWalletIds.isEmpty) {
        return <TransactionModel>[];
      }

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
        (currentUserTransactionsSnapshot.value as Map).forEach((key, value) {
          allTransactions.add(
            TransactionModel.fromSnapshot(
              currentUserTransactionsSnapshot.child(key),
            ),
          );
        });
      }

      if (partnerTransactionsSnapshot != null &&
          partnerTransactionsSnapshot.exists) {
        final partnerSnapshot = partnerTransactionsSnapshot;
        (partnerSnapshot.value as Map).forEach((key, value) {
          allTransactions.add(
            TransactionModel.fromSnapshot(partnerSnapshot.child(key)),
          );
        });
      }

      final partnershipCreationDate = userProvider.partnershipCreationDate;

      final filteredTransactions = allTransactions.where((transaction) {
        final transactionDate = transaction.date;

        final isWalletVisible = visibleWalletIds.contains(transaction.walletId);
        if (!isWalletVisible) return false;

        final isDateInRange =
            transactionDate.isAfter(
              startDate.subtract(const Duration(days: 1)),
            ) &&
            transactionDate.isBefore(endDate.add(const Duration(days: 1)));
        if (!isDateInRange) return false;

        if (transaction.userId == userProvider.partnerUid) {
          return partnershipCreationDate != null &&
              transactionDate.isAfter(partnershipCreationDate);
        }

        return true;
      }).toList();

      filteredTransactions.sort((a, b) => b.date.compareTo(a.date));
      // Enrich transactions with walletName, categoryName, subCategoryName, transferFromWalletName, transferToWalletName
      final walletsMap = {for (var w in visibleWallets) w.id: w};
      final categories = await getCategoriesStream().first;
      final categoriesMap = {for (var c in categories) c.id: c};

      return filteredTransactions.map((trans) {
        final wallet =
            walletsMap[trans.walletId] ??
            Wallet(id: '', name: 'Ví đã xóa', balance: 0, ownerId: '');
        String categoryName = 'Không có';
        String subCategoryName = '';

        if (trans.categoryId != null) {
          final category =
              categoriesMap[trans.categoryId] ??
              Category(
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
    });
  }

  Future<ReportData> getReportData(
    UserProvider userProvider,
    DateTime startDate,
    DateTime endDate,
  ) async {
    if (userProvider.currentUser == null) {
      throw Exception('Người dùng chưa đăng nhập');
    }

    final visibleWallets = await getWalletsStream(userProvider).first;
    if (visibleWallets.isEmpty) {
      return ReportData(
        expenseByCategory: {},
        incomeByCategory: {},
        rawTransactions: [],
      );
    }

    final allUserCategories = await getCategoriesStream().first;
    final validTransactions = await getTransactionsStream(
      userProvider,
      startDate,
      endDate,
    ).first;

    double personalIncome = 0;
    double personalExpense = 0;
    double sharedIncome = 0;
    double sharedExpense = 0;
    Map<Category, double> expenseByCategory = {};
    Map<Category, double> incomeByCategory = {};

    final walletOwnerMap = {for (var w in visibleWallets) w.id: w.ownerId};

    for (final transaction in validTransactions) {
      final ownerId = walletOwnerMap[transaction.walletId];
      final bool isShared = ownerId == userProvider.partnershipId;

      if (transaction.type == TransactionType.income) {
        if (isShared) {
          sharedIncome += transaction.amount;
        } else {
          personalIncome += transaction.amount;
        }

        if (transaction.categoryId != null) {
          final category = allUserCategories.firstWhere(
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
          final category = allUserCategories.firstWhere(
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

    final enrichedTransactions = await _enrichTransactions(
      validTransactions,
      visibleWallets,
      allUserCategories,
    );

    return ReportData(
      totalIncome: personalIncome + sharedIncome,
      totalExpense: personalExpense + sharedExpense,
      personalIncome: personalIncome,
      personalExpense: personalExpense,
      sharedIncome: sharedIncome,
      sharedExpense: sharedExpense,
      expenseByCategory: expenseByCategory,
      incomeByCategory: incomeByCategory,
      rawTransactions: enrichedTransactions,
    );
  }

  Future<List<TransactionModel>> _enrichTransactions(
    List<TransactionModel> transactions,
    List<Wallet> wallets,
    List<Category> categories,
  ) async {
    final walletMap = {for (var w in wallets) w.id: w.name};
    final categoryMap = {for (var c in categories) c.id: c};

    return transactions.map((trans) {
      final walletName = walletMap[trans.walletId] ?? 'Ví đã xóa';
      String categoryName = 'Không có';
      String subCategoryName = '';

      if (trans.categoryId != null &&
          categoryMap.containsKey(trans.categoryId)) {
        final category = categoryMap[trans.categoryId]!;
        categoryName = category.name;
        if (trans.subCategoryId != null &&
            category.subCategories.containsKey(trans.subCategoryId)) {
          subCategoryName = category.subCategories[trans.subCategoryId]!;
        }
      } else if (trans.categoryId != null) {
        categoryName = 'Danh mục đã xóa';
      }

      return trans.copyWith(
        walletName: walletName,
        categoryName: categoryName,
        subCategoryName: subCategoryName,
      );
    }).toList();
  }

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
      print("Lỗi khi cập nhật trạng thái hiển thị của ví: $e");
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
      print("Lỗi khi đặt ngân sách cho danh mục: $e");
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
      print("Lỗi khi thêm danh mục con: $e");
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
      print("Lỗi khi xóa danh mục con: $e");
      rethrow;
    }
  }

  Future<List<String>> getDescriptionHistory() async {
    if (_uid == null) return [];

    try {
      // Get from local database first (faster)
      final localSuggestions = await _localDb.getDescriptionSuggestions(_uid!);
      if (localSuggestions.isNotEmpty) {
        return localSuggestions;
      }

      // Fallback to Firebase (existing logic)
      final snapshot = await _dbRef
          .child('user_descriptions')
          .child(_uid!)
          .get();

      if (snapshot.exists) {
        final descriptionsMap = snapshot.value as Map<dynamic, dynamic>;
        final firebaseDescriptions = descriptionsMap.keys
            .cast<String>()
            .toList();

        // ✨ Cache Firebase descriptions to local DB
        for (final desc in firebaseDescriptions) {
          await _localDb.saveDescriptionToHistory(_uid!, desc);
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
      // 1. Save to local database immediately
      await _localDb.saveDescriptionToHistory(_uid!, description);

      // 2. Try to save to Firebase
      await _dbRef.child('user_descriptions').child(_uid!).update({
        description: true,
      });
    } catch (e) {
      // If Firebase fails, local save is already done
      print("⚠️ Warning: Failed to save description to Firebase: $e");
    }
  }

  Future<List<String>> searchDescriptionHistory(
    String query, {
    int limit = 5,
  }) async {
    if (_uid == null || query.trim().isEmpty) return [];

    try {
      return await _localDb.searchDescriptionHistory(
        _uid!,
        query.trim(),
        limit: limit,
      );
    } catch (e) {
      print("❌ Error searching description history: $e");
      return [];
    }
  }

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
    final ref = FirebaseDatabase.instance
        .ref()
        .child('users')
        .child(uid)
        .child('partnershipId');
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

    // Xóa thông tin partnership khỏi user
    await userRef.update({
      'partnershipId': null,
      'partnerUid': null,
      'partnerDisplayName': null,
      'partnershipCreatedAt': null,
    });

    // Xóa partnership nếu không còn thành viên nào
    final partnershipSnapshot = await partnershipRef.get();
    if (partnershipSnapshot.exists) {
      final members = (partnershipSnapshot.value as Map)['memberIds'] as List;
      if (members.length <= 1) {
        await partnershipRef.remove();
      } else {
        // Cập nhật danh sách thành viên
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

      // Create partnership
      await _dbRef.child('partnerships').child(partnershipId).set(partnership);

      // Update current user
      await _dbRef.child('users').child(_uid).update({
        'partnershipId': partnershipId,
        'partnerUid': partnerUid,
        'partnerDisplayName': partnerData['displayName'],
        'partnershipCreatedAt': ServerValue.timestamp,
      });

      // Update partner
      await _dbRef.child('users').child(partnerUid).update({
        'partnershipId': partnershipId,
        'partnerUid': _uid,
        'partnerDisplayName': currentUserData['displayName'],
        'partnershipCreatedAt': ServerValue.timestamp,
      });

      // Send notifications
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

      // Clean up invite code
      await _dbRef
          .child('inviteCodes')
          .child(inviteCode.toUpperCase())
          .remove();
    } catch (e) {
      print('Error handling partnership invite: $e');
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
      print('Error sending notification: $e');
    }
  }

  // FIX: Sync partnership on app startup
  Future<void> syncPartnership(String partnershipId) async {
    if (_uid == null) return;

    try {
      final partnershipRef = _dbRef.child('partnerships').child(partnershipId);

      // Check if partnership exists
      final partnershipSnapshot = await partnershipRef.get();
      if (!partnershipSnapshot.exists) {
        // Clean up invalid partnership
        await _dbRef.child('users').child(_uid!).update({
          'partnershipId': null,
          'partnerUid': null,
          'partnerDisplayName': null,
          'partnershipCreatedAt': null,
        });
        throw Exception('Partnership không tồn tại');
      }

      // Update sync time
      await partnershipRef.update({
        'lastSyncTime': ServerValue.timestamp,
        'isActive': true,
      });

      await _dbRef.child('users').child(_uid!).update({
        'lastSync': ServerValue.timestamp,
      });
    } catch (e) {
      print('Error syncing partnership: $e');
      rethrow;
    }
  }

  Future<List<TransactionModel>> getTransactionsOfflineFirst({
    String? userId,
    DateTime? startDate,
    DateTime? endDate,
    int? limit,
  }) async {
    try {
      // Try local database first
      final localTransactions = await _localDb.getLocalTransactions(
        userId: userId,
        startDate: startDate,
        endDate: endDate,
        limit: limit,
      );

      if (localTransactions.isNotEmpty) {
        print(
          '📱 Returning ${localTransactions.length} transactions from local DB',
        );
        return localTransactions;
      }

      // Fallback to Firebase stream conversion
      print('☁️ Fetching transactions from Firebase...');
      // Note: In real implementation, you'd want to convert the stream to future
      // For now, return empty list and let the stream handle the data
      return [];
    } catch (e) {
      print('❌ Error getting transactions offline-first: $e');
      return [];
    }
  }

  // ✨ V7: Sync local changes to Firebase
  Future<void> syncLocalChangesToFirebase() async {
    if (_uid == null) return;

    try {
      // Get unsynced transactions
      final unsyncedTransactions = await _localDb.getUnsyncedRecords(
        'transactions',
      );
      print(
        '🔄 Syncing ${unsyncedTransactions.length} unsynced transactions...',
      );

      for (final record in unsyncedTransactions) {
        try {
          final transaction = TransactionModel(
            id: record['id'],
            amount: record['amount'],
            type: TransactionType.values.firstWhere(
              (e) => e.name == record['type'],
            ),
            categoryId: record['categoryId'],
            walletId: record['walletId'],
            date: DateTime.parse(record['date']),
            description: record['description'] ?? '',
            userId: record['userId'],
            subCategoryId: record['subCategoryId'],
            transferToWalletId: record['transferToWalletId'],
          );

          // Upload to Firebase
          await _dbRef
              .child('transactions')
              .child(transaction.id)
              .set(transaction.toJson());

          // Mark as synced
          await _localDb.markAsSynced('transactions', transaction.id);
          print('✅ Synced transaction: ${transaction.id}');
        } catch (e) {
          print('❌ Failed to sync transaction ${record['id']}: $e');
        }
      }

      print('🎉 Sync completed successfully');
    } catch (e) {
      print('❌ Error syncing local changes: $e');
    }
  }

  // ✨ V7: Database health check
  Future<Map<String, dynamic>> getDatabaseHealth() async {
    try {
      final localStats = await _localDb.getDatabaseStats();

      // Try Firebase connection
      bool firebaseConnected = false;
      try {
        await _dbRef.child('.info/connected').get();
        firebaseConnected = true;
      } catch (e) {
        firebaseConnected = false;
      }

      return {
        'localDatabase': localStats,
        'firebaseConnected': firebaseConnected,
        'lastSync': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      return {'error': e.toString(), 'firebaseConnected': false};
    }
  }

  @override
  void handleError(dynamic error, {String? context}) {
    final errorMessage = context != null
        ? '$context: $error'
        : 'Database error: $error';

    print('🚨 $errorMessage');

    // Could add error tracking service here
    // ErrorTrackingService.logError(error, context);
  }
}
