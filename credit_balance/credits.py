
import bisect

def logf(func):
    def new(*args, **kwargs):
        print(f"Calling {func.__name__} with args: {args}, kwargs: {kwargs}")
        result = func(*args, **kwargs)
        print(f"{func.__name__} returned: {result}")
        return result
    return new


class Credits:
    def __init__(self):
        self.timestamps = []
        self.grants = {}
        self.grants_ts = {}
        self.exp_ts = {}
        self.subtracts_ts = {}
        self.subtractions = []
    
    def create_grant(self, timestamp: int, grant_id: str, amount: int, expiration_timestamp: int):
        bisect.insort(self.timestamps, timestamp)
        self.grants_ts[timestamp] = self.grants_ts.get(timestamp, [])
        self.grants_ts[timestamp].append(grant_id)
        self.grants[grant_id] = {
                "ts": timestamp,
                "gid": grant_id,
                "amt": amount,
                "ets": expiration_timestamp
            }
        bisect.insort(self.timestamps, expiration_timestamp)
        self.exp_ts[expiration_timestamp] = self.exp_ts.get(expiration_timestamp, [])
        self.exp_ts[expiration_timestamp].append(grant_id)

    def subtract(self, timestamp: int, amount: int):
        self.subtractions.append({"ts": timestamp, "amt": amount})
        bisect.insort(self.timestamps, timestamp)
        self.subtracts_ts[timestamp] = self.subtracts_ts.get(timestamp, 0) + amount

    # @logf
    def get_balance(self, timestamp: int):
        available_expirations = set()
        grant_amts =  {}
        for ts in self.timestamps:
            # print(f"grant_amts: {grant_amts}")
            # print(f"available_expirations: {available_expirations}")
            if ts > timestamp:
                break
            o1, o2, o3 = (
                self.grants_ts.get(ts, []), 
                self.exp_ts.get(ts, []),
                self.subtracts_ts.get(ts, 0)
            )
            # print(ts, o1, o2, o3)
            # counter update
            for gid in o1:
                grant_amts[gid] = self.grants[gid]["amt"]
                available_expirations.add(gid)

            for gid in o2:
                if gid in grant_amts:
                    del grant_amts[gid]
                    available_expirations.remove(gid)

            # subtract  
            if o3 > 0:
                to_reduce = o3
                _available_expirations = sorted(available_expirations, key=lambda x: self.grants[x]["ets"])
                for gid in _available_expirations:
                    if grant_amts[gid] > to_reduce:
                        grant_amts[gid] -= to_reduce
                        to_reduce = 0
                        break
                    else:
                        to_reduce -= grant_amts[gid]
                        del grant_amts[gid]
                        available_expirations.remove(gid)
                if to_reduce > 0:
                    return None
                
        return sum(grant_amts.values())




        

