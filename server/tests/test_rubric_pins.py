from app.rubric import load_rubric


def test_rubric_version_and_weights_are_pinned():
    """Cache invalidation rests on the version string: the review cache key
    includes rubric version (main.py _review_cache_keys), so editing weights
    WITHOUT bumping the version leaves every cached verdict — computed under
    the old weights — served as if it were the new rubric. This test is the
    tripwire: any change to version or weights must be a deliberate edit of
    this file too (AGENTS.md: the weights are a proposal until the
    supervisor's real marking sheet replaces them)."""
    rubric = load_rubric()
    assert rubric["version"] == "v3"
    weights = {name: float(c["weight"]) for name, c in rubric["quality_criteria"].items()}
    assert weights == {"clear": 0.25, "testable": 0.4, "complete": 0.2, "consistent": 0.15}
    # Provenance must keep saying "proposal": if the supervisor's real rubric
    # ever lands, the sentence changes and this assertion should fail loudly.
    assert "starting proposal" in rubric["provenance"]
