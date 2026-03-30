class Animal:
    def __init__(self, name, species):
        self.name = name
        self.species = species

    def speak(self):
        raise NotImplementedError

    def describe(self):
        return f"{self.name} is a {self.species}"


class Dog(Animal):
    def __init__(self, name):
        super().__init__(name, "Canis lupus familiaris")

    def speak(self):
        return "Woof!"

    def fetch(self, item):
        return f"{self.name} fetches the {item}"


def train(dog, commands):
    results = {}
    for command in commands:
        if command == "sit":
            results[command] = f"{dog.name} sits"
        elif command == "stay":
            results[command] = f"{dog.name} stays"
        elif command == "fetch":
            results[command] = dog.fetch("ball")
    return results


@staticmethod
def utility_function(x, y):
    return x + y


class Kennel:
    def __init__(self):
        self.dogs = []

    def add_dog(self, dog):
        self.dogs.append(dog)

    def remove_dog(self, name):
        self.dogs = [d for d in self.dogs if d.name != name]

    def list_dogs(self):
        return [d.name for d in self.dogs]


def main():
    kennel = Kennel()
    dog1 = Dog("Rex")
    dog2 = Dog("Buddy")
    kennel.add_dog(dog1)
    kennel.add_dog(dog2)
    print(kennel.list_dogs())
    print(train(dog1, ["sit", "stay", "fetch"]))


if __name__ == "__main__":
    main()
