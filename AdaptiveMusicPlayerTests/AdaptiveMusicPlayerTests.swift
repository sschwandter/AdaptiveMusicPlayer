import Testing
import AVFoundation
@testable import AdaptiveMusicPlayer

@Suite("AudioPlayer Tests")
@MainActor
struct AudioPlayerTests {
    
    @Test("AudioPlayer initializes with default values")
    func initialState() async throws {
        let player = AudioPlayer()
        
        #expect(player.isPlaying == false)
        #expect(player.currentTime == 0)
        #expect(player.duration == 0)
        #expect(player.volume == 1.0)
        #expect(player.currentFileName == nil)
        #expect(player.fileSampleRate == 0)
        #expect(player.hardwareSampleRate > 0) // Should get system default
        #expect(player.statusMessage == "")
        #expect(player.hasError == false)
        #expect(player.isLoading == false)
    }
    
    @Test("Volume changes are applied correctly")
    func volumeControl() async throws {
        let player = AudioPlayer()
        
        player.volume = 0.8
        #expect(player.volume == 0.8)
        
        player.volume = 0.0
        #expect(player.volume == 0.0)
        
        player.volume = 1.0
        #expect(player.volume == 1.0)
    }
    
    @Test("Time formatting works correctly")
    func timeFormatting() async throws {
        // Test various time formats using TimeFormatter directly
        #expect(TimeFormatter.format(0) == "0:00")
        #expect(TimeFormatter.format(30) == "0:30")
        #expect(TimeFormatter.format(60) == "1:00")
        #expect(TimeFormatter.format(90) == "1:30")
        #expect(TimeFormatter.format(3661) == "61:01")
    }
    
    @Test("Toggle play/pause with no file loaded")
    func toggleWithoutFile() async throws {
        let player = AudioPlayer()
        
        // Should remain stopped when no file is loaded
        player.togglePlayPause()
        #expect(player.isPlaying == false)
    }
    
    @Test("Stop functionality")
    func stopFunctionality() async throws {
        let player = AudioPlayer()
        
        // Stopping when not playing should be safe
        player.stop()
        #expect(player.isPlaying == false)
        #expect(player.currentTime == 0)
    }
    
    @Test("Skip operations without file")
    func skipWithoutFile() async throws {
        let player = AudioPlayer()
        
        // Should be safe to call skip functions without a file
        player.skipForward()
        player.skipBackward()
        
        #expect(player.currentTime == 0)
        #expect(player.isPlaying == false)
    }
    
    @Test("Seek bounds checking")
    func seekBounds() async throws {
        let player = AudioPlayer()
        
        // Should handle seeking without a file gracefully
        player.seek(to: 10.0)
        #expect(player.currentTime == 0)
        
        player.seek(to: -5.0)
        #expect(player.currentTime == 0)
    }
    
    @Test("Error state management")
    func errorStates() async throws {
        let player = AudioPlayer()

        // Initially no error
        #expect(player.hasError == false)

        // Test loading a non-existent file
        let invalidURL = URL(fileURLWithPath: "/nonexistent/file.mp3")
        await player.loadFile(url: invalidURL)

        // Should have error state
        #expect(player.hasError == true)
        #expect(!player.statusMessage.isEmpty)
    }
}

@Suite("TimeFormatter Tests")
struct TimeFormatterTests {

    @Test("Time string formatting edge cases")
    func timeStringEdgeCases() async throws {
        // Test edge cases using TimeFormatter directly
        #expect(TimeFormatter.format(0.5) == "0:00")
        #expect(TimeFormatter.format(59.9) == "0:59")
        #expect(TimeFormatter.format(3600) == "60:00")
        #expect(TimeFormatter.format(Double.infinity) == "0:00") // Invalid input returns 0:00
        #expect(TimeFormatter.format(-10) == "0:00") // Negative should be handled gracefully
    }
}

