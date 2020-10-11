import os
import tensorflow as tf
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import functools
import csv
test_file_path = [
    r"I:\csgoserver\steamcmd\steamapps\common\Counter-Strike Global Offensive Beta - Dedicated Server\csgo\addons\sourcemod\test_data.csv"]

train_file_path = [
    r"I:\csgoserver\steamcmd\steamapps\common\Counter-Strike Global Offensive Beta - Dedicated Server\csgo\addons\sourcemod\train_data.csv"]

csv_data = []
csv_data_x = []
csv_data_y = []
csv_data_all_num = []
csv_data_y_avg = {}
with open(train_file_path[0], 'r') as f:
    reader = csv.reader(f)
    for row in reader:
        csv_data.append(row)
csv_data_x = csv_data[0]
for index in range(1, len(csv_data)):
    for zeus in range(len(csv_data[index])):
        if csv_data_x[zeus] == 'is_cheat':
            continue
        if csv_data_x[zeus] in csv_data_y_avg.keys():
            csv_data_y_avg[csv_data_x[zeus]] = float(
                csv_data_y_avg[csv_data_x[zeus]]) + float(csv_data[index][zeus])

        else:
            csv_data_y_avg[csv_data_x[zeus]] = float(csv_data[index][zeus])
for key in csv_data_y_avg:
    csv_data_y_avg[key] = float(csv_data_y_avg[key]) / float(len(csv_data) - 1)

print(csv_data_y_avg)


def process_continuous_data(mean, data):
    data = tf.cast(data, tf.float32) * 1/(2*mean)
    return tf.reshape(data, [-1, 1])


def create_model():
    numerical_columns = []
    for feature in csv_data_y_avg.keys():
        num_col = tf.feature_column.numeric_column(
            feature, normalizer_fn=functools.partial(process_continuous_data, csv_data_y_avg[feature]))
        numerical_columns.append(num_col)
    preprocessing_layer = tf.keras.layers.DenseFeatures(numerical_columns)
    model = tf.keras.models.Sequential([
        preprocessing_layer,
        tf.keras.layers.Dense(128, activation='relu'),
        tf.keras.layers.Dense(128, activation='relu'),
        tf.keras.layers.Dense(1, activation='sigmoid'),
    ])

    model.compile(optimizer='adam',
                  loss=tf.losses.BinaryCrossentropy(
                      from_logits=True),
                  metrics=['accuracy'])

    return model


def get_dataset(file_path):
    dataset = tf.data.experimental.make_csv_dataset(
        file_path,
        batch_size=32,
        label_name='is_cheat',
        na_value="?",
        num_epochs=1,
        ignore_errors=True)
    return dataset


def start_predict():
    test_data = get_dataset(test_file_path)
    print(test_data)
    test_loss, test_accuracy = model.evaluate(test_data)
    predict_data = model.predict(test_data)
    print("anti-aimbot model, accuracy:{:5.2f}%".format(100 * test_accuracy))
    num_cheat = 0
    for pre, result in zip(predict_data[:20], list(test_data)[0][1][:20]):
        num_access = 100 * pre[0]
        if num_access >= 60:
            num_cheat = num_cheat + 1
        print("player is aimbot :{:5.2f}% ".format(
            num_access), " is cheat: ", ("yes" if bool(result) else "no"))

    print("result:", num_cheat)
    if len(predict_data) < 20:
        print("player kill must > 20")
    if num_cheat >= (len(predict_data) / 2) - 2:
        print("player is aimbot")
    else:
        print("player is not aimbot")


model = create_model()
model.load_weights('./save/model_weight')
start_predict()
while True:
    input("any key ...")
    start_predict()
