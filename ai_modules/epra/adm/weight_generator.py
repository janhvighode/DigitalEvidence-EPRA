class WeightGenerator:
    """
    Generates base weights based on
    the ADM decision path.
    """

    BASE_WEIGHTS = {
        0: 0.40,
        1: 0.25,
        2: 0.15,
        3: 0.10,
        4: 0.10
    }

    def generate(self, decision_path):
        """
        Returns weights for each ADM factor.
        """

        weights = {}

        for index, factor in enumerate(decision_path):
            weights[factor] = self.BASE_WEIGHTS[index]

        return weights