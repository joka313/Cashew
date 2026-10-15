import 'dart:async';

import 'package:budget/database/tables.dart';

// Shared budgets synced through the original app's Firebase project, which
// this fork cannot use, so Firebase was removed. The functions keep their
// old signatures for the rest of the app and do nothing.

Timer? cloudTimeoutTimer;

Future<bool> shareBudget(Budget? budgetToShare, context) async => false;

Future<bool> removedSharedFromBudget(Budget sharedBudget,
        {bool removeFromServer = true}) async =>
    false;

Future<bool> leaveSharedBudget(Budget sharedBudget) async => false;

Future<bool> addMemberToBudget(
        String sharedKey, String member, Budget budget) async =>
    false;

Future<bool> removeMemberFromBudget(
        String sharedKey, String member, Budget budget) async =>
    false;

Future<dynamic> getMembersFromBudget(String sharedKey, Budget budget) async =>
    null;

Future<bool> getCloudBudgets() async => false;

Future<bool> sendTransactionSet(Transaction transaction, Budget budget) async =>
    false;

Future<bool> sendTransactionAdd(Transaction transaction, Budget budget) async =>
    false;

Future<bool> sendTransactionDelete(
        Transaction transaction, Budget budget) async =>
    false;

Future<bool> syncPendingQueueOnServer() async => false;

Future<bool> updateTransactionOnServerAfterChangingCategoryInformation(
        TransactionCategory category) async =>
    false;
