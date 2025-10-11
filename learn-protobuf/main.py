import message_pb2


person = message_pb2.Person()
person.name = "John ➤ Doe"
person.id = 123
person.email = "john.doe@example.com"


serialized_data = person.SerializeToString()
print(f"Serialized data: {serialized_data}")

