from datetime import datetime


class TimelineService:

    @staticmethod
    def generate_timeline(case_id, events):
        """
        Generate investigation timeline.
        """

        timeline = []

        for index, event in enumerate(events, start=1):

            timeline.append({
                "step": index,
                "case_id": case_id,
                "event": event,
                "timestamp": datetime.now().strftime("%d-%m-%Y %H:%M:%S")
            })

        return timeline