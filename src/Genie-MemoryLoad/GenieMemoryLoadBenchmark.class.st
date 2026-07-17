"
I measure how Pharo behaves under memory load: time to allocate N bytes of
live objects, time to full-GC over them, time to snapshot the image with the
load live, and time to release it all.

Run one tier per fresh VM launch so runs are independent:

	GenieMemoryLoadBenchmark run1GB.
	GenieMemoryLoadBenchmark run10GB.
	GenieMemoryLoadBenchmark run100GB.
	GenieMemoryLoadBenchmark run1TB.
	GenieMemoryLoadBenchmark runTierBytes: 5 * 1073741824 mode: #byteArrays snapshot: false.

Modes:
- #smallObjects — chunks of 16384 seven-slot Arrays (64 bytes each on 64-bit
  Spur): billions of pointer objects, the GC-hostile shape.
- #byteArrays — 1 MiB ByteArray per chunk: raw allocation, cheap to mark.

Each run answers a Dictionary of metrics and emits the same data as one JSON
line on the Transcript (stdout when headless), so a shell runner can collect
results even if a later phase dies. Progress is logged every GiB.

Mind the machine: a tier needs roughly 1.3x its size in RAM and, when
snapshot is enabled, the same again in free disk for the image file. See
docs/memory-load.md for the run protocol and host sizing.
"
Class {
	#name : 'GenieMemoryLoadBenchmark',
	#superclass : 'Object',
	#instVars : [
		'mode',
		'targetBytes',
		'withSnapshot',
		'keep',
		'results',
		'gcBaseline'
	],
	#category : 'Genie-MemoryLoad',
	#package : 'Genie-MemoryLoad'
}

{ #category : 'running' }
GenieMemoryLoadBenchmark class >> gigabytes: aNumber [
	^ self runTierBytes: (aNumber * 1073741824) rounded mode: #smallObjects snapshot: true
]

{ #category : 'running' }
GenieMemoryLoadBenchmark class >> run100GB [
	^ self gigabytes: 100
]

{ #category : 'running' }
GenieMemoryLoadBenchmark class >> run10GB [
	^ self gigabytes: 10
]

{ #category : 'running' }
GenieMemoryLoadBenchmark class >> run1GB [
	^ self gigabytes: 1
]

{ #category : 'running' }
GenieMemoryLoadBenchmark class >> run1TB [
	^ self gigabytes: 1024
]

{ #category : 'running' }
GenieMemoryLoadBenchmark class >> runTierBytes: byteCount mode: aSymbol snapshot: aBoolean [
	^ self new
		  targetBytes: byteCount;
		  mode: aSymbol;
		  withSnapshot: aBoolean;
		  run
]

{ #category : 'chunk geometry' }
GenieMemoryLoadBenchmark >> bytesPerLeaf [
	"8-byte Spur header + 7 slots * 8 bytes."
	^ 64
]

{ #category : 'chunk geometry' }
GenieMemoryLoadBenchmark >> chunkBytes [
	mode == #byteArrays ifTrue: [ ^ 1048576 ].
	^ self leavesPerChunk * self bytesPerLeaf
]

{ #category : 'chunk geometry' }
GenieMemoryLoadBenchmark >> chunkOverheadBytes [
	"The spine Array holding the leaves (or the ByteArray's own header)."
	mode == #byteArrays ifTrue: [ ^ 16 ].
	^ self leavesPerChunk * 8 + 16
]

{ #category : 'chunk geometry' }
GenieMemoryLoadBenchmark >> effectiveChunkBytes [
	^ self chunkBytes + self chunkOverheadBytes
]

{ #category : 'reporting' }
GenieMemoryLoadBenchmark >> emitResult [
	self log: (self jsonFor: results)
]

{ #category : 'vm statistics' }
GenieMemoryLoadBenchmark >> heapBytes [
	"VM parameter 3: end of object memory, i.e. current heap size in bytes."
	^ Smalltalk vm parameterAt: 3
]

{ #category : 'vm statistics' }
GenieMemoryLoadBenchmark >> imageFileBytes [
	^ [ Smalltalk imagePath asFileReference size ] on: Error do: [ -1 ]
]

{ #category : 'initialization' }
GenieMemoryLoadBenchmark >> initialize [
	super initialize.
	mode := #smallObjects.
	targetBytes := 1073741824.
	withSnapshot := false
]

{ #category : 'reporting' }
GenieMemoryLoadBenchmark >> json: aValue on: aStream [
	(aValue == true or: [ aValue == false ])
		ifTrue: [ ^ aStream nextPutAll: aValue printString ].
	aValue isNumber ifTrue: [ ^ aStream nextPutAll: aValue printString ].
	aStream
		nextPut: $";
		nextPutAll: aValue asString;
		nextPut: $"
]

{ #category : 'reporting' }
GenieMemoryLoadBenchmark >> jsonFor: aDictionary [
	"Render as one JSON object with sorted keys. Values are numbers, booleans,
	 strings or symbols we produced ourselves — no escaping needed."
	^ String streamContents: [ :s |
		  | first |
		  s nextPut: ${.
		  first := true.
		  (aDictionary keys asSortedCollection: [ :a :b | a asString <= b asString ])
			  do: [ :key |
				  first ifFalse: [ s nextPut: $, ].
				  first := false.
				  s
					  nextPut: $";
					  nextPutAll: key asString;
					  nextPut: $";
					  nextPut: $:.
				  self json: (aDictionary at: key) on: s ].
		  s nextPut: $} ]
]

{ #category : 'chunk geometry' }
GenieMemoryLoadBenchmark >> leavesPerChunk [
	^ 16384
]

{ #category : 'reporting' }
GenieMemoryLoadBenchmark >> log: aString [
	Transcript
		show: aString;
		cr;
		flush
]

{ #category : 'reporting' }
GenieMemoryLoadBenchmark >> logProgress: chunkIndex of: chunkCount since: startMs [
	self log: (String streamContents: [ :s |
			 s nextPutAll: 'allocated '.
			 s print: chunkIndex * self effectiveChunkBytes // 1048576.
			 s nextPutAll: ' MiB ('.
			 s print: chunkIndex.
			 s nextPutAll: '/'.
			 s print: chunkCount.
			 s nextPutAll: ' chunks), elapsed '.
			 s print: Time millisecondClockValue - startMs.
			 s nextPutAll: ' ms, heap '.
			 s print: self heapBytes // 1048576.
			 s nextPutAll: ' MiB' ])
]

{ #category : 'accessing' }
GenieMemoryLoadBenchmark >> mode: aSymbol [
	mode := aSymbol
]

{ #category : 'chunk geometry' }
GenieMemoryLoadBenchmark >> newChunk [
	mode == #byteArrays ifTrue: [ ^ ByteArray new: self chunkBytes ].
	^ (1 to: self leavesPerChunk) collect: [ :each | Array new: 7 ]
]

{ #category : 'measuring' }
GenieMemoryLoadBenchmark >> recordGCBaseline [
	gcBaseline := Dictionary new.
	gcBaseline at: #scavengeCount put: self statScavengeCount.
	gcBaseline at: #scavengeMs put: self statScavengeMs.
	gcBaseline at: #fullGCCount put: self statFullGCCount.
	gcBaseline at: #fullGCMs put: self statFullGCMs
]

{ #category : 'measuring' }
GenieMemoryLoadBenchmark >> recordGCDeltas [
	results at: #scavengeCount put: self statScavengeCount - (gcBaseline at: #scavengeCount).
	results at: #scavengeMs put: self statScavengeMs - (gcBaseline at: #scavengeMs).
	results at: #fullGCCount put: self statFullGCCount - (gcBaseline at: #fullGCCount).
	results at: #fullGCMs put: self statFullGCMs - (gcBaseline at: #fullGCMs)
]

{ #category : 'accessing' }
GenieMemoryLoadBenchmark >> results [
	^ results
]

{ #category : 'running' }
GenieMemoryLoadBenchmark >> run [
	"Allocate the tier, full-GC over it, optionally snapshot with it live,
	 then release it. Answer the metrics Dictionary (also emitted as JSON)."
	results := Dictionary new.
	results at: #mode put: mode.
	results at: #targetBytes put: targetBytes.
	results at: #pharoVersion put: self systemVersionString.
	Smalltalk garbageCollect.
	results at: #heapBytesBefore put: self heapBytes.
	self recordGCBaseline.
	self timeAllocation.
	results at: #heapBytesAfterAlloc put: self heapBytes.
	self recordGCDeltas.
	results at: #fullGCAtLoadMs put: (Time millisecondsToRun: [ Smalltalk garbageCollect ]).
	(withSnapshot and: [ self timeSnapshot ]) ifTrue: [ ^ results ].
	self timeRelease.
	self emitResult.
	^ results
]

{ #category : 'vm statistics' }
GenieMemoryLoadBenchmark >> statFullGCCount [
	"VM parameter 7: full GCs since startup."
	^ Smalltalk vm parameterAt: 7
]

{ #category : 'vm statistics' }
GenieMemoryLoadBenchmark >> statFullGCMs [
	"VM parameter 8: total milliseconds in full GCs since startup."
	^ Smalltalk vm parameterAt: 8
]

{ #category : 'vm statistics' }
GenieMemoryLoadBenchmark >> statScavengeCount [
	"VM parameter 9: incremental GCs (scavenges) since startup."
	^ Smalltalk vm parameterAt: 9
]

{ #category : 'vm statistics' }
GenieMemoryLoadBenchmark >> statScavengeMs [
	"VM parameter 10: total milliseconds in scavenges since startup."
	^ Smalltalk vm parameterAt: 10
]

{ #category : 'vm statistics' }
GenieMemoryLoadBenchmark >> systemVersionString [
	^ [ Smalltalk version asString ] on: Error do: [ 'unknown' ]
]

{ #category : 'accessing' }
GenieMemoryLoadBenchmark >> targetBytes: byteCount [
	targetBytes := byteCount
]

{ #category : 'measuring' }
GenieMemoryLoadBenchmark >> timeAllocation [
	| chunkCount chunksPerGiB started |
	chunkCount := (targetBytes / self effectiveChunkBytes) ceiling.
	chunksPerGiB := (1073741824 // self effectiveChunkBytes) max: 1.
	keep := OrderedCollection new: chunkCount.
	started := Time millisecondClockValue.
	1 to: chunkCount do: [ :i |
		keep add: self newChunk.
		i \\ chunksPerGiB = 0 ifTrue: [ self logProgress: i of: chunkCount since: started ] ].
	results at: #chunkCount put: chunkCount.
	results at: #estimatedBytes put: chunkCount * self effectiveChunkBytes.
	results at: #allocMs put: Time millisecondClockValue - started.
	results at: #allocMBPerSecond put:
		(((results at: #estimatedBytes) / 1048576.0 / (((results at: #allocMs) max: 1) / 1000.0)) roundTo: 0.1)
]

{ #category : 'measuring' }
GenieMemoryLoadBenchmark >> timeRelease [
	keep := nil.
	results at: #releaseMs put: (Time millisecondsToRun: [ Smalltalk garbageCollect ]).
	results at: #heapBytesAfterRelease put: self heapBytes
]

{ #category : 'measuring' }
GenieMemoryLoadBenchmark >> timeSnapshot [
	"Snapshot with the load still live. Answer true when this execution is the
	 copy resumed later from the snapshot file — it must not re-run the tail."
	| marker ms |
	marker := [ Smalltalk session ] on: Error do: [ nil ].
	ms := Time millisecondsToRun: [ Smalltalk snapshot: true andQuit: false ].
	(marker notNil and: [ ([ Smalltalk session ] on: Error do: [ nil ]) ~~ marker ])
		ifTrue: [
			self log: '{"resumedFromSnapshot":true}'.
			^ true ].
	results at: #snapshotMs put: ms.
	results at: #imageFileBytes put: self imageFileBytes.
	^ false
]

{ #category : 'accessing' }
GenieMemoryLoadBenchmark >> withSnapshot: aBoolean [
	withSnapshot := aBoolean
]
