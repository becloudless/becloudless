
Features have a higher priority than fields. Meaning that if a resource field is an array, a feature will override any manually set values.
example: you cannot set `pod.tolerations`, without disable `features.scheduling`.

