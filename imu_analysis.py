import json
import numpy as np
import matplotlib.pyplot as plt
from math import sqrt

def calculate_vector_length(vector):
    """Calculate the length (magnitude) of a 3D vector."""
    return sqrt(vector['x']**2 + vector['y']**2 + vector['z']**2)

def analyze_imu_data(file_path):
    # Load the IMU data from JSON file
    with open(file_path, 'r') as f:
        data = json.load(f)
    
    # Extract accelerometer, gyroscope, and orientation data
    accel_data = []
    gyro_data = []
    timestamps = []
    pitch_values = []
    roll_values = []
    
    for entry in data:
        if 'accelerometer' in entry and 'gyroscope' in entry and 'orientation' in entry:
            accel_data.append([
                entry['accelerometer']['x'],
                entry['accelerometer']['y'],
                entry['accelerometer']['z']
            ])
            
            gyro_data.append([
                entry['gyroscope']['x'],
                entry['gyroscope']['y'],
                entry['gyroscope']['z']
            ])
            
            timestamps.append(entry['timestamp'])
            pitch_values.append(entry['orientation']['pitch'])
            roll_values.append(entry['orientation']['roll'])
    
    # Convert to numpy arrays for easier calculations
    accel_data = np.array(accel_data)
    gyro_data = np.array(gyro_data)
    timestamps = np.array(timestamps)
    
    # Adjust accelerometer data by removing gravity (1g) from z-axis
    gravity_adjusted_accel = accel_data.copy()
    gravity_adjusted_accel[:, 2] += 1.0  # Add 1g to z-axis (assuming z is negative due to gravity)
    
    # Calculate accelerometer noise and bias
    accel_lengths = np.sqrt(np.sum(accel_data**2, axis=1))
    accel_noise = np.std(accel_lengths)
    accel_bias = np.mean(gravity_adjusted_accel, axis=0)  # [bias_x, bias_y, bias_z]
    accel_bias_length = np.linalg.norm(accel_bias)
    
    # Calculate gyroscope noise and bias
    gyro_lengths = np.sqrt(np.sum(gyro_data**2, axis=1))
    gyro_noise = np.std(gyro_lengths)
    gyro_bias = np.mean(gyro_data, axis=0)  # [bias_x, bias_y, bias_z]
    gyro_bias_length = np.linalg.norm(gyro_bias)
    
    # Print the results
    print("\n--- IMU Analysis Results ---")
    print("\nAccelerometer:")
    print(f"  Noise (std of vector lengths): {accel_noise:.6f}")
    print(f"  Bias (average of vectors, gravity adjusted): [{accel_bias[0]:.6f}, {accel_bias[1]:.6f}, {accel_bias[2]:.6f}]")
    print(f"  Bias vector length: {accel_bias_length:.6f}")
    
    print("\nGyroscope:")
    print(f"  Noise (std of vector lengths): {gyro_noise:.6f}")
    print(f"  Bias (average of vectors): [{gyro_bias[0]:.6f}, {gyro_bias[1]:.6f}, {gyro_bias[2]:.6f}]")
    print(f"  Bias vector length: {gyro_bias_length:.6f}")
    
    # Plot pitch and roll over time
    plt.figure(figsize=(12, 6))
    
    # Adjust timestamps to start from 0
    if len(timestamps) > 0:
        adjusted_timestamps = timestamps - timestamps[0]
    else:
        adjusted_timestamps = timestamps
    
    # Plot pitch
    plt.subplot(2, 1, 1)
    plt.plot(adjusted_timestamps, pitch_values, 'b-', label='Pitch')
    plt.title('Pitch over Time')
    plt.xlabel('Time (seconds)')
    plt.ylabel('Pitch (radians)')
    plt.grid(True)
    plt.legend()
    
    # Plot roll
    plt.subplot(2, 1, 2)
    plt.plot(adjusted_timestamps, roll_values, 'r-', label='Roll')
    plt.title('Roll over Time')
    plt.xlabel('Time (seconds)')
    plt.ylabel('Roll (radians)')
    plt.grid(True)
    plt.legend()
    
    #add a title for the whole figure
    plt.suptitle('Pitch and Roll Time Series'+ file_path[0:3])
    plt.tight_layout()
    plt.savefig('pitch_roll_time_series' + file_path[0:3] + '.png')
    plt.show()
    
    return {
        'accel_noise': accel_noise,
        'accel_bias': accel_bias,
        'gyro_noise': gyro_noise,
        'gyro_bias': gyro_bias
    }


if __name__ == "__main__":
    file_path = "1.json"
    results = analyze_imu_data(file_path)
    file_path = "2.json"
    results = analyze_imu_data(file_path)

    # Save your JSON data to a file named 'imu_data.json' or adjust the file path
    file_path = "accelerometerOnly.json"
    results = analyze_imu_data(file_path)
    '''
    Accelerometer:
    Noise (std of vector lengths): 0.000564
    Bias (average of vectors, gravity adjusted): [0.001561, -0.000920, 0.001461]
    Bias vector length: 0.002328

    Gyroscope:
    Noise (std of vector lengths): 0.001435
    Bias (average of vectors): [-0.005218, -0.000900, -0.004836]
    Bias vector length: 0.007171
    '''

    file_path = 'gyroscopeOnly.json'
    results = analyze_imu_data(file_path)
    '''
    Accelerometer:
    Noise (std of vector lengths): 0.000644
    Bias (average of vectors, gravity adjusted): [0.001612, -0.000941, 0.001288]
    Bias vector length: 0.002267

    Gyroscope:
    Noise (std of vector lengths): 0.002020
    Bias (average of vectors): [-0.005191, -0.000889, -0.004821]
    Bias vector length: 0.007140
    '''

    file_path = 'complementaryFilter.json'
    results = analyze_imu_data(file_path)
    '''
    Accelerometer:
    Noise (std of vector lengths): 0.000562
    Bias (average of vectors, gravity adjusted): [0.002281, -0.000402, 0.001466]
    Bias vector length: 0.002741

    Gyroscope:
    Noise (std of vector lengths): 0.001501
    Bias (average of vectors): [-0.005228, -0.000839, -0.004885]
    Bias vector length: 0.007205
    '''
