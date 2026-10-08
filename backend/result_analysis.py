"""Evidence summaries from persisted local grades. This module never grades images."""


def enrich_answers(grade, questions):
    """Use the assessment's saved question records as analysis context.

    The locally evaluated correctness is retained; AI does not re-grade marks.
    """
    result = dict(grade)
    enriched = []
    for item in grade.get("answers") or []:
        if not isinstance(item, dict):
            continue
        answer = {key: item.get(key) for key in (
            "question_number", "question_id", "answer", "isCorrect",
            "isAmbiguous", "confidence", "multipleAnswers", "options",
        ) if key in item}
        question = questions.get(str(item.get("question_id")))
        source = question or item
        for key in ("question_text", "question_type", "correct_answer", "topic_tag"):
            if source.get(key) is not None:
                answer[key] = source[key]
        enriched.append(answer)
    result["answers"] = enriched
    return result


def question_counts(grades):
    counts = {}
    for grade in grades:
        for answer in grade.get("answers") or []:
            key = str(answer.get("question_id") or answer.get("question_number") or "unknown")
            row = counts.setdefault(key, {
                "question_id": answer.get("question_id"),
                "question_text": answer.get("question_text"),
                "topic_tag": answer.get("topic_tag"),
                "correct_answer": answer.get("correct_answer"),
                "correct": 0, "total": 0, "ambiguous": 0,
                "selected_answers": {},
            })
            row["total"] += 1
            row["correct"] += answer.get("isCorrect") is True
            row["ambiguous"] += answer.get("isAmbiguous") is True
            selected = str(answer.get("answer") or "Blank")
            row["selected_answers"][selected] = row["selected_answers"].get(selected, 0) + 1
    return list(counts.values())


def grade_context(grade):
    total = grade.get("total_questions") or 0
    score = grade.get("score") or 0
    return {
        "score": score,
        "total_questions": total,
        "percentage": round(score / total * 100, 1) if total else 0,
        "answers": grade.get("answers") or [],
    }


def topic_counts(grades):
    topics = {}
    for grade in grades:
        for answer in grade.get("answers") or []:
            topic = answer.get("topic_tag") or "Unspecified topic"
            counts = topics.setdefault(topic, {"correct": 0, "total": 0, "ambiguous": 0})
            counts["total"] += 1
            counts["correct"] += answer.get("isCorrect") is True
            counts["ambiguous"] += answer.get("isAmbiguous") is True
    return topics


def class_summary(grades):
    """A clearly labelled, non-AI fallback when generation is unavailable."""
    count = len(grades)
    average = sum(grade_context(g)["percentage"] for g in grades) / count
    insights = f"{count} saved {'result' if count == 1 else 'results'} with an average score of {average:.1f}%. "
    if count == 1:
        insights += "This is preliminary evidence from one submission; it does not establish a class-wide pattern. "
    topics = topic_counts(grades)
    if topics:
        insights += "Topic results: " + "; ".join(
            f"{topic}: {values['correct']}/{values['total']} correct"
            for topic, values in topics.items()
        ) + ". "
        if any(t["ambiguous"] for t in topics.values()):
            insights += "Some marks are ambiguous and need instructor review before drawing conclusions. "
        gaps = [topic for topic, values in topics.items() if values["correct"] < values["total"]]
        recommendations = (
            "Review the missed items in " + ", ".join(gaps) + ". Model a worked example, then check understanding with a short practice activity."
            if gaps else
            "Reinforce the demonstrated concepts with an application exercise and use a follow-up question to check retention."
        )
    else:
        insights += "Only total scores were saved; topic-level strengths and misconceptions cannot be established."
        recommendations = "Review the marked paper with the learner and identify the items that need practice. Save item evaluations in the next scanning session for topic-specific feedback."
    return {"insights": insights.strip(), "recommendations": recommendations}


def student_summary(grade):
    context = grade_context(grade)
    topics = topic_counts([grade])
    strengths = [
        f"{topic}: {values['correct']}/{values['total']} correct."
        for topic, values in topics.items() if values["correct"] > 0
    ]
    gaps = [
        f"Revisit {topic}: {values['total'] - values['correct']} item(s) need review."
        for topic, values in topics.items() if values["correct"] < values["total"]
    ]
    summary = f"You scored {context['score']} out of {context['total_questions']} ({context['percentage']:.1f}%). "
    if not topics:
        summary += "Your item answers were not saved with this older result, so specific learning gaps cannot be identified."
    else:
        summary += "Use the answer evaluation below to review your work and plan your next practice session."
    return {
        "performanceSummary": summary,
        "strengths": strengths,
        "learningGaps": gaps,
        "actionableSteps": [
            "Review each missed or unclear item with your instructor and explain the correct answer in your own words."
            if gaps or not topics else
            "Practice applying these concepts to new examples, then revisit them after a few days."
        ],
    }


def student_overview_summary(results, released_only=True):
    """A clearly labelled, non-AI fallback across a student's whole history."""
    count = len(results)
    if count == 0:
        return {
            "performanceSummary": "No released results are available to summarize yet.",
            "strengths": [],
            "learningGaps": [],
            "actionableSteps": ["Complete and release a graded assessment to receive personal analysis."],
        }
    average = sum(r["percentage"] for r in results) / count
    topics = topic_counts(results)
    summary = (
        f"Across {count} {'released' if released_only else 'saved'} {'assessment' if count == 1 else 'assessments'}, "
        f"your average score is {average:.1f}%. "
    )
    strengths = [
        f"{topic}: {values['correct']}/{values['total']} correct."
        for topic, values in topics.items() if values["correct"] > 0
    ]
    gaps = [
        f"Revisit {topic}: {values['total'] - values['correct']} item(s) need review."
        for topic, values in topics.items() if values["correct"] < values["total"]
    ]
    if not topics:
        summary += "Only total scores were saved for your earlier results, so topic-level strengths cannot be identified."
    else:
        summary += "Review the topic breakdown below to plan your next study session."
    return {
        "performanceSummary": summary,
        "strengths": strengths,
        "learningGaps": gaps,
        "actionableSteps": [
            "Revisit the missed topics with a focused practice set, then re-check your understanding with a short self-quiz."
            if gaps or not topics else
            "Challenge yourself with harder, mixed-topic questions to consolidate your knowledge."
        ],
    }
