import 'package:flutter/material.dart';

import '../../widgets/background_design.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/left_panel.dart';
import '../../widgets/right_panel.dart';
import '../../utils/responsive.dart';

class CreateAccountScreen extends StatelessWidget {
  const CreateAccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final bool mobile = Responsive.isMobile(context);

    return Scaffold(
      body: Stack(
        children: [
          const BackgroundDesign(),

          SafeArea(
            child: SingleChildScrollView(
              child: Center(
                child: Padding(
                  padding: Responsive.pagePadding(context),
                  child: SizedBox(
                    width: Responsive.cardWidth(context),
                    child: GlassCard(
                      child: mobile
                          // MOBILE / ANDROID
                          ? Column(
                              children: const [
                                LeftPanel(),

                                SizedBox(height: 20),

                                RightPanel(),
                              ],
                            )

                          // DESKTOP / CHROME
                          : SizedBox(
                              height: 720,
                              child: Row(
                                crossAxisAlignment:
                                    CrossAxisAlignment.stretch,
                                children: const [
                                  Expanded(
                                    flex: 3,
                                    child: LeftPanel(),
                                  ),

                                  Expanded(
                                    flex: 2,
                                    child: RightPanel(),
                                  ),
                                ],
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}