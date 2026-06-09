Class {
	#name : #GenieSettings,
	#superclass : #Object,
	#instVars : [
		'data'
	],
	#category : #Genie
}

{ #category : #'instance creation' }
GenieSettings class >> defaultCopied [
	^ self new initializeDefaults
]

{ #category : #accessing }
GenieSettings >> asDictionary [
	^ data copy
]

{ #category : #accessing }
GenieSettings >> at: aKey [
	^ data at: aKey
]

{ #category : #accessing }
GenieSettings >> at: aKey put: aValue [
	^ data at: aKey put: aValue
]

{ #category : #initialization }
GenieSettings >> initializeDefaults [
	data := Dictionary new.
	data at: #stackSize put: 100.
	^ self
]

{ #category : #accessing }
GenieSettings >> stackSize [
	^ data at: #stackSize ifAbsent: [ 100 ]
]
