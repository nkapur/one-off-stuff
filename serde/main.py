"""
KV store deserialization module.

What types should I keep in mind?
- Primitive types (int, float, str, bool)
- Collections (list, dict)
- Custom objects (classes) (v2)

Compression? (v2)

subcall of WRITE, UPDATE or READ operations
"""
from dataclasses import dataclass


import json

@dataclass
class Row:
    key: str
    value: str


class Serializable:
    """
    Base class for every Serializable object derived class
    """
    def __string__(self) -> str:
        raise NotImplemented("")
    

@dataclass
class Base:
    number: int
    text: str

@dataclass
class KVObject(Serializable):
    field1: str
    field2: str
    base: Base

    def __metadata__(self) -> dict:
        return self.fields()


    def __string__(self) -> str:
        return json.dumps({"key": self.key, "value": self.value})
