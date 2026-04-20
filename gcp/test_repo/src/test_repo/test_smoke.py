def test_import():
    import test_repo
    assert test_repo.__version__ == "0.0.1"
