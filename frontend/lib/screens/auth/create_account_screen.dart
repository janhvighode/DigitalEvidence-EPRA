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
            child: Center(
              child: Padding(
                padding: Responsive.pagePadding(context),
                child: SizedBox(
                  width: Responsive.cardWidth(context),
                  child: GlassCard(
                    child: mobile

                        ? SingleChildScrollView(
                            child: Column(
                              children: const [

                                LeftPanel(),

                                SizedBox(height: 30),

                                RightPanel(),

                              ],
                            ),
                          )

                        : SizedBox(
                            height: 720,
                            child: Row(
                              children: const [

                                LeftPanel(),

                                RightPanel(),

                              ],
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