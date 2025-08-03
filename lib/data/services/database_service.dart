import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import 'package:moneysun/data/models/budget_model.dart';
import 'package:moneysun/data/models/transaction_model.dart';
import 'package:moneysun/data/models/wallet_model.dart';
import 'package:moneysun/data/models/report_data_model.dart'; // Import model mới
import 'package:moneysun/data/models/category_model.dart'; // Import Category
import 'package:moneysun/data/providers/user_provider.dart';
import 'package:async/async.dart';
import 'package:collection/collection.dart';

class DatabaseService {
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();
  final String? _uid = FirebaseAuth.instance.currentUser?.uid;

  Stream<List<TransactionModel>> getRecentTransactionsStream(
    UserProvider userProvider, {
    int limit = 15,
  }) {
    if (_uid == null) return Stream.value([]);

    // 1. Lấy stream của các ví và các danh mục
    final walletsStream = getWalletsStream(userProvider);
    final categoriesStream = getCategoriesStream();

    // 2. Lấy stream của các giao dịch gần đây
    final transRef = _dbRef
        .child('transactions')
        .orderByChild('userId')
        .equalTo(_uid)
        .limitToLast(limit);
    final recentTransStream = transRef.onValue.map((event) {
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
    });

    // 3. Sử dụng StreamZip để kết hợp 3 stream lại với nhau
    // Nó sẽ chỉ phát ra một giá trị mới khi TẤT CẢ các stream con đều có dữ liệu.
    return StreamZip([walletsStream, categoriesStream, recentTransStream]).map((
      results,
    ) {
      final List<Wallet> wallets = results[0] as List<Wallet>;
      final List<Category> categories = results[1] as List<Category>;
      final List<TransactionModel> transactions =
          results[2] as List<TransactionModel>;

      // 4. "Làm giàu" dữ liệu giao dịch
      return transactions.map((trans) {
        final walletName = wallets
            .firstWhere(
              (w) => w.id == trans.walletId,
              orElse: () =>
                  Wallet(id: '', name: 'Ví đã xóa', balance: 0, ownerId: ''),
            )
            .name;
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

        return trans.copyWith(
          walletName: walletName,
          categoryName: categoryName,
          subCategoryName: subCategoryName,
        );
      }).toList();
    });
  }

  // Lấy danh sách các ví của user dưới dạng một Stream (tự động cập nhật)
  Stream<List<Wallet>> getWalletsStream(UserProvider userProvider) {
    if (_uid == null)
      return Stream.value([]); // Trả về list rỗng nếu chưa đăng nhập

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

    // Query một lần để lấy tất cả các ví có khả năng hiển thị
    return _dbRef.child('wallets').onValue.map((event) {
      final List<Wallet> visibleWallets = [];
      if (event.snapshot.exists) {
        final allWalletsMap = event.snapshot.value as Map<dynamic, dynamic>;
        allWalletsMap.forEach((key, value) {
          final walletSnapshot = event.snapshot.child(key);
          final wallet = Wallet.fromSnapshot(walletSnapshot);

          // Áp dụng các quy tắc hiển thị:
          // 1. Ví của chính mình: Luôn hiển thị
          if (wallet.ownerId == _uid) {
            visibleWallets.add(wallet);
          }
          // 2. Ví chung: Luôn hiển thị
          else if (wallet.ownerId == pId) {
            visibleWallets.add(wallet);
          }
          // 3. Ví của partner: Chỉ hiển thị nếu isVisibleToPartner = true
          else if (wallet.ownerId == partnerUid && wallet.isVisibleToPartner) {
            visibleWallets.add(wallet);
          }
        });
      }
      return visibleWallets;
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
        ownerId: ownerId, // <-- Sử dụng ownerId được truyền vào
        isVisibleToPartner: true, // Mặc định ví mới luôn hiển thị
      );
      await newWalletRef.set(newWallet.toJson());
    } catch (e) {
      print("Lỗi khi thêm ví: $e");
      rethrow;
    }
  }

  Future<void> addCategory(String name, String type) async {
    // Thêm type
    if (_uid == null) return;
    final newCategoryRef = _dbRef.child('categories').child(_uid!).push();
    final newCategory = Category(
      id: newCategoryRef.key!,
      name: name,
      ownerId: _uid!,
      type: type, // Gán type
    );
    await newCategoryRef.set(newCategory.toJson());
  }

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

  Future<void> addTransaction(TransactionModel transaction) async {
    if (_uid == null) return;

    // 1. Lưu giao dịch vào database
    final newTransactionRef = _dbRef.child('transactions').push();
    await newTransactionRef.set(transaction.toJson());

    // 2. Cập nhật số dư của ví tương ứng
    final walletRef = _dbRef.child('wallets').child(transaction.walletId);
    final walletSnapshot = await walletRef.get();

    if (walletSnapshot.exists) {
      final currentBalance = (walletSnapshot.child('balance').value as num)
          .toDouble();
      double newBalance;
      if (transaction.type == 'income') {
        newBalance = currentBalance + transaction.amount; // ✅ Đúng
      } else if (transaction.type == 'expense') {
        newBalance = currentBalance - transaction.amount; // ✅ Đúng
      } else {
        // Xử lý riêng cho transfer
        newBalance = currentBalance - transaction.amount;
      }
      await walletRef.update({'balance': newBalance});
    }

    if (transaction.description.isNotEmpty) {
      await saveDescriptionToHistory(transaction.description);
    }
  }

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

    // 2. Xử lý cập nhật số dư ví
    final newWalletRef = _dbRef.child('wallets').child(newTransaction.walletId);
    final oldWalletRef = _dbRef.child('wallets').child(oldTransaction.walletId);

    // Nếu ví không thay đổi
    if (newTransaction.walletId == oldTransaction.walletId) {
      // Tính toán chênh lệch
      double oldAmountValue = oldTransaction.type == TransactionType.income
          ? oldTransaction.amount
          : -oldTransaction.amount;
      double newAmountValue = newTransaction.type == TransactionType.income
          ? newTransaction.amount
          : -newTransaction.amount;
      double difference = newAmountValue - oldAmountValue;
      await newWalletRef
          .child('balance')
          .set(ServerValue.increment(difference));
    }
    // Nếu ví thay đổi
    else {
      // Hoàn tác giao dịch cũ: Cộng lại số tiền đã chi, trừ đi số tiền đã thu
      double oldAmountReversal = oldTransaction.type == TransactionType.income
          ? -oldTransaction.amount
          : oldTransaction.amount;
      await oldWalletRef
          .child('balance')
          .set(ServerValue.increment(oldAmountReversal));

      // Áp dụng giao dịch mới
      double newAmountValue = newTransaction.type == TransactionType.income
          ? newTransaction.amount
          : -newTransaction.amount;
      await newWalletRef
          .child('balance')
          .set(ServerValue.increment(newAmountValue));
    }

    // 3. (Tùy chọn) Lưu mô tả mới vào lịch sử
    if (newTransaction.description.isNotEmpty) {
      await saveDescriptionToHistory(newTransaction.description);
    }
  }

  Future<void> deleteTransaction(TransactionModel transaction) async {
    if (_uid == null) return;

    try {
      // 1. Xóa bản ghi giao dịch
      await _dbRef.child('transactions').child(transaction.id).remove();

      // 2. Hoàn tác ảnh hưởng lên số dư ví
      final walletRef = _dbRef.child('wallets').child(transaction.walletId);
      // Tính toán giá trị hoàn tác: nếu là thu nhập thì trừ đi, nếu là chi tiêu thì cộng lại
      final reversalAmount = transaction.type == TransactionType.income
          ? -transaction.amount
          : transaction.amount;

      await walletRef
          .child('balance')
          .set(ServerValue.increment(reversalAmount));

      // Logic cho giao dịch chuyển tiền (phức tạp hơn, cần xóa cả 2 giao dịch)
      // Tạm thời bỏ qua để giữ cho chức năng cơ bản hoạt động.
    } catch (e) {
      print("Lỗi khi xóa giao dịch: $e");
      rethrow;
    }
  }

  // (Bên trong class DatabaseService)

  Stream<List<TransactionModel>> getTransactionsStream(
    UserProvider userProvider,
    DateTime startDate,
    DateTime endDate,
  ) {
    if (userProvider.currentUser == null) {
      return Stream.value([]); // Trả về stream rỗng ngay lập tức
    }

    // 1. Lấy stream của các ví có thể xem
    return getWalletsStream(userProvider)
    // 2. Chuyển đổi (map) mỗi danh sách ví thành một danh sách giao dịch
    .asyncMap((visibleWallets) async {
      final visibleWalletIds = visibleWallets.map((w) => w.id).toSet();
      if (visibleWalletIds.isEmpty) {
        return <TransactionModel>[]; // Trả về danh sách rỗng cho lần emit này
      }

      // 3. Thực hiện query một lần để lấy tất cả các giao dịch liên quan
      // Query theo userId của mình và của partner để thu hẹp phạm vi tìm kiếm
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

      // Xử lý giao dịch của người dùng hiện tại
      if (currentUserTransactionsSnapshot.exists) {
        (currentUserTransactionsSnapshot.value as Map).forEach((key, value) {
          allTransactions.add(
            TransactionModel.fromSnapshot(
              currentUserTransactionsSnapshot.child(key),
            ),
          );
        });
      }
      // Xử lý giao dịch của partner
      if (partnerTransactionsSnapshot != null &&
          partnerTransactionsSnapshot.exists) {
        // 1. Tạo một biến cục bộ, non-nullable sau khi đã kiểm tra null
        final partnerSnapshot = partnerTransactionsSnapshot;

        // 2. Sử dụng biến cục bộ này một cách an toàn
        (partnerSnapshot.value as Map).forEach((key, value) {
          allTransactions.add(
            TransactionModel.fromSnapshot(partnerSnapshot.child(key)),
          );
        });
      }

      final partnershipCreationDate = userProvider.partnershipCreationDate;

      // 4. Lọc kết quả trên client
      final filteredTransactions = allTransactions.where((transaction) {
        final transactionDate = transaction.date;

        // Điều kiện 1: Giao dịch phải thuộc một trong các ví được xem
        final isWalletVisible = visibleWalletIds.contains(transaction.walletId);
        if (!isWalletVisible) return false;

        // Điều kiện 2: Ngày giao dịch phải nằm trong khoảng thời gian yêu cầu
        final isDateInRange =
            transactionDate.isAfter(
              startDate.subtract(const Duration(days: 1)),
            ) &&
            transactionDate.isBefore(endDate.add(const Duration(days: 1)));
        if (!isDateInRange) return false;

        // Điều kiện 3: Nếu là của partner, phải xảy ra sau khi kết nối
        if (transaction.userId == userProvider.partnerUid) {
          return partnershipCreationDate != null &&
              transactionDate.isAfter(partnershipCreationDate);
        }

        // Giao dịch của mình thì luôn hợp lệ
        return true;
      }).toList();

      // 5. Sắp xếp và trả về
      filteredTransactions.sort((a, b) => b.date.compareTo(a.date));
      return filteredTransactions;
    });
  }

  // (Bên trong class DatabaseService)

  Future<ReportData> getReportData(
    UserProvider userProvider,
    DateTime startDate,
    DateTime endDate,
  ) async {
    if (userProvider.currentUser == null) {
      throw Exception('Người dùng chưa đăng nhập');
    }

    // Bước 1: Lấy tất cả các ví mà người dùng có thể xem
    final visibleWallets = await getWalletsStream(userProvider).first;
    if (visibleWallets.isEmpty) {
      // Nếu không có ví nào, không thể có dữ liệu báo cáo
      return ReportData(
        expenseByCategory: {},
        incomeByCategory: {},
        rawTransactions: [],
      );
    }

    // Bước 2: Lấy tất cả danh mục của người dùng
    final allUserCategories = await getCategoriesStream().first;

    // Bước 3: Lấy tất cả các giao dịch trong khoảng thời gian yêu cầu
    // Sử dụng lại hàm getTransactionsStream đã được tối ưu
    final validTransactions = await getTransactionsStream(
      userProvider,
      startDate,
      endDate,
    ).first;

    // Bước 4: Khởi tạo các biến để tổng hợp dữ liệu
    double personalIncome = 0;
    double personalExpense = 0;
    double sharedIncome = 0;
    double sharedExpense = 0;
    Map<Category, double> expenseByCategory = {};
    Map<Category, double> incomeByCategory = {};

    // Tạo một Map để tra cứu nhanh xem một ví là chung hay riêng
    final walletOwnerMap = {for (var w in visibleWallets) w.id: w.ownerId};

    // Bước 5: Lặp qua các giao dịch hợp lệ để tính toán
    for (final transaction in validTransactions) {
      // Xác định giao dịch là cá nhân hay chung
      final ownerId = walletOwnerMap[transaction.walletId];
      final bool isShared = ownerId == userProvider.partnershipId;

      if (transaction.type == TransactionType.income) {
        if (isShared) {
          sharedIncome += transaction.amount;
        } else {
          personalIncome += transaction.amount;
        }

        // Tổng hợp thu nhập theo danh mục
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

        // Tổng hợp chi tiêu theo danh mục
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

    // Bước 6: "Làm giàu" dữ liệu giao dịch để hiển thị trên UI
    // (Ví dụ: thêm tên ví, tên danh mục)
    final enrichedTransactions = await _enrichTransactions(
      validTransactions,
      visibleWallets,
      allUserCategories,
    );

    // Bước 7: Trả về đối tượng ReportData hoàn chỉnh
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

  // HÀM HELPER: Để "làm giàu" dữ liệu giao dịch
  Future<List<TransactionModel>> _enrichTransactions(
    List<TransactionModel> transactions,
    List<Wallet> wallets,
    List<Category> categories,
  ) async {
    // Tạo Map để tra cứu nhanh, tránh lặp nhiều lần
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

    // Tạo giao dịch CHI PHÍ từ ví nguồn
    final expenseTrans = TransactionModel(
      id: '',
      amount: amount,
      type: TransactionType.expense,
      walletId: fromWalletId,
      date: date,
      description: 'Chuyển đến: $toWalletName', // Mô tả rõ ràng hơn
      userId: userId,
      transferToWalletId: toWalletName,
    );

    // Tạo giao dịch THU NHẬP cho ví đích
    final incomeTrans = TransactionModel(
      id: '',
      amount: amount,
      type: TransactionType.income,
      walletId: toWalletId,
      date: date,
      description: 'Nhận từ: $fromWalletName', // Mô tả rõ ràng hơn
      userId: userId,
      transferToWalletId: toWalletName,
    );

    // Lưu cả hai giao dịch vào database
    final DatabaseReference transRef = _dbRef.child('transactions');
    await transRef.push().set(expenseTrans.toJson());
    await transRef.push().set(incomeTrans.toJson());

    // Cập nhật số dư cho cả hai ví
    final fromWalletRef = _dbRef.child('wallets').child(fromWalletId);
    final toWalletRef = _dbRef.child('wallets').child(toWalletId);

    await fromWalletRef.child('balance').set(ServerValue.increment(-amount));
    await toWalletRef.child('balance').set(ServerValue.increment(amount));

    final fromWalletSnapshot = await _dbRef
        .child('wallets')
        .child(fromWalletId)
        .get();
    final toWalletSnapshot = await _dbRef
        .child('wallets')
        .child(toWalletId)
        .get();

    if (fromWalletSnapshot.exists) {
      await fromWalletRef.child('balance').set(ServerValue.increment(-amount));
    }
    if (toWalletSnapshot.exists) {
      await toWalletRef.child('balance').set(ServerValue.increment(amount));
    }
  }

  Stream<Budget?> getBudgetForMonthStream(String month) {
    // month format: "yyyy-MM"
    if (_uid == null) return Stream.value(null);

    final budgetRef = _dbRef
        .child('budgets')
        .orderByChild('ownerId_month') // Cần tạo key kết hợp để query
        .equalTo('${_uid}_$month');

    return budgetRef.onValue.map((event) {
      if (event.snapshot.exists && event.snapshot.children.isNotEmpty) {
        // Chỉ lấy bản ghi đầu tiên tìm thấy
        return Budget.fromSnapshot(event.snapshot.children.first);
      }
      return null;
    });
  }

  // Lưu hoặc cập nhật ngân sách
  Future<void> saveBudget(Budget budget) async {
    if (_uid == null) return;

    DatabaseReference ref;
    // Nếu budget đã có ID, nghĩa là cập nhật
    if (budget.id.isNotEmpty) {
      ref = _dbRef.child('budgets').child(budget.id);
    } else {
      // Nếu không, tạo mới
      ref = _dbRef.child('budgets').push();
    }

    // Tạo key kết hợp để có thể query hiệu quả
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
      // Chúng ta sử dụng đường dẫn trực tiếp đến map 'categoryAmounts' và đặt giá trị cho key là categoryId
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
      // Firebase tự động tạo một key duy nhất cho danh mục con
      final subCategoryRef = _dbRef
          .child('categories')
          .child(_uid!)
          .child(parentCategoryId)
          .child('subCategories')
          .push();

      // Gán tên cho key vừa tạo
      await subCategoryRef.set(subCategoryName);
    } catch (e) {
      print("Lỗi khi thêm danh mục con: $e");
      rethrow;
    }
  }

  // Xóa một danh mục con
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
      final snapshot = await _dbRef
          .child('user_descriptions')
          .child(_uid!)
          .get();
      if (snapshot.exists) {
        final descriptionsMap = snapshot.value as Map<dynamic, dynamic>;
        // Chuyển keys của Map thành một List<String>
        return descriptionsMap.keys.cast<String>().toList();
      }
      return [];
    } catch (e) {
      print("Lỗi khi lấy lịch sử mô tả: $e");
      return [];
    }
  }

  Future<void> saveDescriptionToHistory(String description) async {
    if (_uid == null || description.isEmpty) return;
    try {
      // Chúng ta dùng `update` để thêm một key mới mà không ghi đè toàn bộ node
      await _dbRef.child('user_descriptions').child(_uid!).update({
        description: true,
      });
    } catch (e) {
      print("Lỗi khi lưu mô tả: $e");
      // Bỏ qua lỗi này vì nó không quá quan trọng
    }
  }

  Stream<List<TransactionModel>> getTransactionsForCategoryStream({
    required UserProvider userProvider,
    required String categoryId,
    required DateTime startDate,
    required DateTime endDate,
  }) async* {
    // Sử dụng lại hàm getTransactionsStream đã có và lọc trên client.
    // Đây là cách tiếp cận đơn giản nhất với cấu trúc hiện tại.
    // Trong một DB lớn hơn, query trực tiếp trên server sẽ tốt hơn.
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

  // HÀM MỚI: Xử lý dữ liệu cho Line Chart
  // Dữ liệu trả về: Map<Tên tháng, Tổng tiền>
  Map<String, double> groupTransactionsByMonth(
    List<TransactionModel> transactions,
  ) {
    final DateFormat formatter = DateFormat(
      'MMM yyyy',
      'vi_VN',
    ); // Định dạng "Thg 7 2025"

    // Sử dụng `groupBy` từ package `collection`
    final groupedByMonth = groupBy(transactions, (TransactionModel t) {
      return formatter.format(t.date);
    });

    // Tính tổng cho mỗi tháng
    return groupedByMonth.map((month, transList) {
      final total = transList.fold(0.0, (sum, item) => sum + item.amount);
      return MapEntry(month, total);
    });
  }
}
