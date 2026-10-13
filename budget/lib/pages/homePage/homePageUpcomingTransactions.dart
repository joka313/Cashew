import 'package:budget/colors.dart';
import 'package:budget/database/tables.dart';
import 'package:budget/pages/upcomingOverdueTransactionsPage.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/framework/popupFramework.dart';
import 'package:budget/widgets/navigationFramework.dart';
import 'package:budget/widgets/openBottomSheet.dart';
import 'package:budget/widgets/periodCyclePicker.dart';
import 'package:budget/widgets/util/keepAliveClientMixin.dart';
import 'package:budget/widgets/transactionsAmountBox.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:timer_builder/timer_builder.dart';

class HomePageUpcomingTransactions extends StatelessWidget {
  const HomePageUpcomingTransactions({super.key});

  @override
  Widget build(BuildContext context) {
    return KeepAliveClientMixin(
      child: Padding(
        padding:
            const EdgeInsetsDirectional.only(bottom: 13, start: 13, end: 13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Since the query uses DateTime.now()
            // We need to refresh every so often to get new data...
            // Is there a better way to do this? listen to database updates?
            TimerBuilder.periodic(Duration(seconds: 5), builder: (context) {
              return Expanded(
                child: TransactionsAmountBox(
                  openPage:
                      UpcomingOverdueTransactions(overdueTransactions: false),
                  label: "upcoming".tr(),
                  absolute: false,
                  totalWithCountStream:
                      database.watchTotalWithCountOfUpcomingOverdue(
                    allWallets: Provider.of<AllWallets>(context),
                    isOverdueTransactions: false,
                    followCustomPeriodCycle: true,
                    cycleSettingsExtension: "OverdueUpcoming",
                    forcedDateTimeRange: upcomingFutureDaysRange(),
                  ),
                  textColor: getColor(context, "unPaidUpcoming"),
                  onLongPress: () async {
                    await openOverdueUpcomingSettings(context);
                    homePageStateKey.currentState?.refreshState();
                  },
                ),
              );
            }),
            SizedBox(width: 13),
            TimerBuilder.periodic(Duration(seconds: 5), builder: (context) {
              return Expanded(
                child: TransactionsAmountBox(
                  openPage:
                      UpcomingOverdueTransactions(overdueTransactions: true),
                  label: "overdue".tr(),
                  absolute: false,
                  totalWithCountStream:
                      database.watchTotalWithCountOfUpcomingOverdue(
                    allWallets: Provider.of<AllWallets>(context),
                    isOverdueTransactions: true,
                    followCustomPeriodCycle: true,
                    cycleSettingsExtension: "OverdueUpcoming",
                  ),
                  textColor: getColor(context, "unPaidOverdue"),
                  onLongPress: () async {
                    await openOverdueUpcomingSettings(context);
                    homePageStateKey.currentState?.refreshState();
                  },
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

// "Past days" counts back from today, which suits overdue transactions. Upcoming
// transactions are all in the future, so for them count the days forward.
DateTimeRange? upcomingFutureDaysRange() {
  if (appStateSettings["selectedPeriodCycleTypeOverdueUpcoming"] !=
      CycleType.pastDays.index) return null;
  int days = appStateSettings["customPeriodPastDaysOverdueUpcoming"] ?? 0;
  DateTime now = DateTime.now();
  return DateTimeRange(
    start: DateTime(now.year, now.month, now.day),
    end: DateTime(now.year, now.month, now.day + days, 23, 59, 59),
  );
}

Future openOverdueUpcomingSettings(BuildContext context) {
  return openBottomSheet(
    context,
    PopupFramework(
      title: "overdue-and-upcoming".tr(),
      subtitle: "applies-to-homepage".tr(),
      child: PeriodCyclePicker(cycleSettingsExtension: "OverdueUpcoming"),
    ),
  );
}
