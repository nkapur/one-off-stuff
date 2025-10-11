from credits import Credits

# Test case 1 - basic subtraction
def test_basic_subtraction():
    credits = Credits()
    credits.subtract(30, amount=1)
    credits.create_grant(10, grant_id="a", amount=1, expiration_timestamp=100)
    assert credits.get_balance(10) == 1
    assert credits.get_balance(30) == 0
    assert credits.get_balance(20) == 1
    print(f"PASSED : {test_basic_subtraction.__name__}")

    # Explanation
    # 10: 1 (a)
    # 20: 1 (a)
    # 30: 0 (a -1)

# Test case 2 - expiration
def test_expiration():
    credits = Credits()
    credits.subtract(30, amount=1)
    credits.create_grant(10, grant_id="a", amount=2, expiration_timestamp=100)
    assert credits.get_balance(10) == 2
    assert credits.get_balance(20) == 2
    assert credits.get_balance(30) == 1
    assert credits.get_balance(100) == 0
    print(f"PASSED : {test_expiration.__name__}")
    # Explanation
    # 10: 2 (a)
    # 20: 2 (a)
    # 30: 1 (a -1)
    # 100: 0 (the remainder of a expired)

# Test case 3 - subtracting from soonest expiring grants first
def test_expiring_grants_soonest():
    credits = Credits()
    credits.create_grant(10, grant_id="a", amount=3, expiration_timestamp=60)
    assert credits.get_balance(10) == 3
    credits.create_grant(20, grant_id="b", amount=2, expiration_timestamp=40)
    credits.subtract(30, amount=1)
    credits.subtract(50, amount=3)
    assert credits.get_balance(10) == 3
    assert credits.get_balance(20) == 5
    assert credits.get_balance(30) == 4
    assert credits.get_balance(40) == 3
    assert credits.get_balance(50) == 0
    print(f"PASSED : {test_expiring_grants_soonest.__name__}")
    # Explanation
    # 10: 3 (a)
    # 20: 5 (a=3, b=2)
    # 30: 4 (subtract 1 from b, so b=1), since it expires first, a=3
    # 40: 3 (b expired)
    # 50: 0 (subtract 3 from a)

# Test case 4 - subtract from many grants
def test_many_grants():
    credits = Credits()
    credits.create_grant(10, grant_id="a", amount=3, expiration_timestamp=60)
    credits.create_grant(20, grant_id="b", amount=2, expiration_timestamp=80)
    credits.subtract(30, amount=4)
    assert credits.get_balance(10) == 3
    assert credits.get_balance(20) == 5
    assert credits.get_balance(30) == 1
    assert credits.get_balance(70) == 1
    print(f"PASSED : {test_many_grants.__name__}")
    # Explanation
    # 10: 3 (a)
    # 20: 5 (a=3, b=2)
    # 30: 1 (subtract 3 from a, 1 from b)
    # 70: 1 (a expired, b=1)

# Test case 5 - not enough credit
def test_insufficient_credit():
    credits = Credits()
    credits.create_grant(10, grant_id="a", amount=3, expiration_timestamp=60)
    credits.subtract(20, amount=4)
    credits.create_grant(40, grant_id="b", amount=10, expiration_timestamp=60)
    assert credits.get_balance(10) == 3
    assert credits.get_balance(20) == None # instead of -1
    assert credits.get_balance(50) == None
    print(f"PASSED : {test_insufficient_credit.__name__}")
    # Explanation
    # 10: 3 (a)
    # 20: None (subtract 4, when only 3 available)
    # 50: None (already went negative, can't recover)

if __name__ == '__main__':
    # import pytest
    # pytest.main()

    test_basic_subtraction()
    test_expiration()
    test_expiring_grants_soonest()
    test_insufficient_credit()
    test_many_grants()

