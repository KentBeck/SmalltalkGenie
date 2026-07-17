Class {
	#name : 'GenieMemoryLoadBenchmarkTest',
	#superclass : 'TestCase',
	#category : 'Genie-MemoryLoad-Tests',
	#package : 'Genie-MemoryLoad',
	#tag : 'Tests'
}

{ #category : 'tests' }
GenieMemoryLoadBenchmarkTest >> testChunkGeometrySmallObjects [
	| bench |
	bench := GenieMemoryLoadBenchmark new.
	self assert: bench chunkBytes equals: 1048576.
	self assert: bench effectiveChunkBytes equals: 1048576 + (16384 * 8) + 16
]

{ #category : 'tests' }
GenieMemoryLoadBenchmarkTest >> testJsonRendering [
	| bench dict |
	bench := GenieMemoryLoadBenchmark new.
	dict := Dictionary new.
	dict at: #b put: 2.5.
	dict at: #a put: 1.
	dict at: #mode put: #smallObjects.
	dict at: #ok put: true.
	self
		assert: (bench jsonFor: dict)
		equals: '{"a":1,"b":2.5,"mode":"smallObjects","ok":true}'
]

{ #category : 'tests' }
GenieMemoryLoadBenchmarkTest >> testNewChunkByteArrays [
	| bench chunk |
	bench := GenieMemoryLoadBenchmark new.
	bench mode: #byteArrays.
	chunk := bench newChunk.
	self assert: chunk class equals: ByteArray.
	self assert: chunk size equals: 1048576
]

{ #category : 'tests' }
GenieMemoryLoadBenchmarkTest >> testNewChunkSmallObjects [
	| chunk |
	chunk := GenieMemoryLoadBenchmark new newChunk.
	self assert: chunk size equals: 16384.
	self assert: chunk first size equals: 7
]

{ #category : 'tests' }
GenieMemoryLoadBenchmarkTest >> testTinyRunProducesMetrics [
	| target result |
	target := 16 * 1024 * 1024.
	result := GenieMemoryLoadBenchmark runTierBytes: target mode: #smallObjects snapshot: false.
	self assert: (result at: #estimatedBytes) >= target.
	self
		assert: (result at: #chunkCount)
		equals: (target / GenieMemoryLoadBenchmark new effectiveChunkBytes) ceiling.
	self assert: (result at: #allocMs) >= 0.
	self assert: (result at: #fullGCAtLoadMs) >= 0.
	self assert: (result at: #scavengeCount) >= 0.
	self assert: (result includesKey: #releaseMs).
	self assert: (result includesKey: #heapBytesAfterRelease).
	self deny: (result includesKey: #snapshotMs)
]
