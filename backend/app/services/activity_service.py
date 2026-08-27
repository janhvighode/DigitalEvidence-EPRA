from datetime import datetime


class ActivityService:

    @staticmethod
    def generate_activity_log(investigator_name, events):
        """
        Generate investigator activity log.
        """

        logs = []

        for event in events:

            logs.append({
                "investigator": investigator_name,
                "activity": event,
                "time": datetime.now().strftime("%d-%m-%Y %H:%M:%S")
            })

        return logs