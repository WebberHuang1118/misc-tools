package main

import (
	"flag"
	"fmt"
	"io"
	"os"
	"sync"
)

const chunkSize = 4096        // Adjust buffer size
const maxBufferedChunks = 100 // Limit the number of buffered chunks

type chunk struct {
	offset int64
	data   []byte
}

func readChunk(file *os.File, offset int64, size int, wg *sync.WaitGroup, out chan<- chunk) {
	defer wg.Done()

	// Create a buffer to hold the data
	buf := make([]byte, size)

	// Read from the specified offset
	_, err := file.ReadAt(buf, offset)
	if err != nil && err != io.EOF {
		fmt.Fprintf(os.Stderr, "Error reading from device at offset %d: %v\n", offset, err)
		return
	}

	// Send the chunk (including offset) to the output channel
	out <- chunk{offset: offset, data: buf}
}

func main() {
	// Parse the block device and output path from the command-line arguments
	devicePath := flag.String("device", "", "Path to the block device (e.g., /dev/sda)")
	outputPath := flag.String("output", "stdout", "Output destination: 'stdout' or a file path")
	flag.Parse()

	if *devicePath == "" {
		fmt.Fprintf(os.Stderr, "Error: block device path is required\n")
		flag.Usage()
		os.Exit(1)
	}

	// Open the block device for reading
	file, err := os.Open(*devicePath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error opening device: %v\n", err)
		os.Exit(1)
	}
	defer file.Close()

	// Get the size of the block device
	info, err := file.Stat()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error getting device info: %v\n", err)
		os.Exit(1)
	}
	deviceSize := info.Size()

	// Set up the output destination (stdout or file)
	var outputWriter io.Writer
	if *outputPath == "stdout" {
		outputWriter = os.Stdout
	} else {
		// Open or create the output file
		outputFile, err := os.Create(*outputPath)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error creating output file: %v\n", err)
			os.Exit(1)
		}
		defer outputFile.Close()
		outputWriter = outputFile
	}

	// Set up a wait group to wait for all goroutines to finish
	var wg sync.WaitGroup

	// Create a channel to receive chunks from goroutines
	out := make(chan chunk, maxBufferedChunks)

	// Map to buffer chunks temporarily
	chunkBuffer := make(map[int64][]byte)
	var mu sync.Mutex

	// Track the next expected offset for writing
	var nextOffset int64 = 0

	// Launch a goroutine to write chunks in order
	go func() {
		for c := range out {
			mu.Lock()
			// Store the chunk in the buffer
			chunkBuffer[c.offset] = c.data

			// Write chunks in order if they are available
			for {
				data, exists := chunkBuffer[nextOffset]
				if !exists {
					break
				}

				// Write the chunk to the output destination
				if _, err := outputWriter.Write(data); err != nil {
					fmt.Fprintf(os.Stderr, "Error writing to output: %v\n", err)
					os.Exit(1)
				}

				// Remove the written chunk from the buffer and move to the next expected offset
				delete(chunkBuffer, nextOffset)
				nextOffset += chunkSize
			}
			mu.Unlock()
		}
	}()

	// Divide the device into chunks and launch goroutines to read each chunk
	for offset := int64(0); offset < deviceSize; offset += chunkSize {
		wg.Add(1)
		go readChunk(file, offset, chunkSize, &wg, out)
	}

	// Wait for all reading goroutines to finish
	wg.Wait()

	// Close the output channel
	close(out)
}
