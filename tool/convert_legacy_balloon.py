"""Convert the pinned ImageTrans Scaled-YOLOv4 CFG/weights to ONNX.
No retraining or quantization; raw activated heads retain Darknet new_coords=1.
Requires numpy and onnx. The generated asset is intentionally not stored in Git.
"""
import argparse
import hashlib
from pathlib import Path
import tempfile
import subprocess
import zipfile
import numpy as np
import onnx
from onnx import helper as h, numpy_helper as nh, TensorProto as T

HASHES = {"model.cfg": "1584e064f6ff8c32c63621a2974cc920f0bd4bc670cf87ca36a2dd7b398963c3", "model.weights": "7bd9c3b91c6c042efbb88115a9e2c495a167d5622da5b45da83a4cceafb82662"}
URL = "https://github.com/Xitaoyou/AiNieePlus/releases/download/manga-models-v1/legacy-balloon-yolov4.zip"

def convert(folder, output):
    for name, digest in HASHES.items():
        if hashlib.sha256((folder/name).read_bytes()).hexdigest() != digest:
            raise ValueError("Unexpected original Legacy file: " + name)
    blocks = []
    for raw in (folder/'model.cfg').read_text().splitlines():
        line = raw.split('#')[0].strip()
        if line.startswith('['): blocks.append({'type':line[1:-1]})
        elif '=' in line:
            k,v=line.split('=',1);blocks[-1][k.strip()]=v.strip()
    weights=np.fromfile(folder/'model.weights',dtype='<f4',offset=20)
    pos=0;nodes=[];initializers=[];layers=[];shapes=[];heads=[]
    def const(name,a):
        initializers.append(nh.from_array(np.asarray(a),name));return name
    def node(op,inputs,name,**kw):
        nodes.append(h.make_node(op,inputs,[name],name=name,**kw));return name
    def take(n):
        nonlocal pos
        a=weights[pos:pos+n].copy();pos+=n
        if len(a)!=n:raise ValueError('Truncated weights')
        return a
    prev='images';shape=[3,512,512]
    for i,b in enumerate(blocks[1:]):
        name=f'l{i}';kind=b['type'];out=prev
        if kind=='convolutional':
            filters=int(b['filters']);k=int(b['size']);stride=int(b.get('stride',1));pad=k//2 if int(b.get('pad',0)) else 0
            bias=take(filters);bn=int(b.get('batch_normalize',0))
            if bn: gamma,mean,var=take(filters),take(filters),take(filters)
            kernel=take(filters*shape[0]*k*k).reshape(filters,shape[0],k,k)
            inputs=[prev,const(name+'_w',kernel)]
            if not bn:inputs.append(const(name+'_b',bias))
            out=node('Conv',inputs,name+'_conv',strides=[stride,stride],pads=[pad]*4,kernel_shape=[k,k])
            if bn:out=node('BatchNormalization',[out,const(name+'_scale',gamma),const(name+'_bias',bias),const(name+'_mean',mean),const(name+'_var',var)],name+'_bn',epsilon=1e-5)
            act=b['activation']
            if act=='mish':out=node('Mul',[out,node('Tanh',[node('Softplus',[out],name+'_softplus')],name+'_tanh')],name+'_mish')
            elif act=='logistic':out=node('Sigmoid',[out],name+'_sigmoid')
            elif act!='linear':raise ValueError(act)
            shape=[filters,(shape[1]+2*pad-k)//stride+1,(shape[2]+2*pad-k)//stride+1]
        elif kind=='route':
            ids=[int(v) for v in b['layers'].split(',')];ids=[i+v if v<0 else v for v in ids]
            out=layers[ids[0]] if len(ids)==1 else node('Concat',[layers[v] for v in ids],name,axis=1)
            shape=[sum(shapes[v][0] for v in ids),*shapes[ids[0]][1:]]
        elif kind=='shortcut':
            out=node('Add',[prev,layers[i+int(b['from'])]],name)
            if b.get('activation','linear')!='linear':raise ValueError('shortcut activation')
        elif kind=='maxpool':
            k=int(b['size']);stride=int(b['stride']);pad=(k-1)//2
            out=node('MaxPool',[prev],name,kernel_shape=[k,k],strides=[stride,stride],pads=[pad]*4)
        elif kind=='upsample':
            s=int(b['stride']);out=node('Resize',[prev,'',const(name+'_scales',np.array([1,1,s,s],np.float32))],name,mode='nearest',coordinate_transformation_mode='asymmetric',nearest_mode='floor');shape=[shape[0],shape[1]*s,shape[2]*s]
        elif kind=='yolo':
            assert b['new_coords']=='1' and b['classes']=='1'
            heads.append(h.make_tensor_value_info(out,T.FLOAT,[1,*shape]))
        else:raise ValueError(kind)
        layers.append(out);shapes.append(shape[:]);prev=out
    assert pos==len(weights),(pos,len(weights))
    graph=h.make_graph(nodes,'ImageTrans Legacy YOLOv4',[h.make_tensor_value_info('images',T.FLOAT,[1,3,512,512])],heads,initializers)
    model=h.make_model(graph,opset_imports=[h.make_opsetid('',13)],producer_name='VeneraX original ImageTrans converter');model.ir_version=8
    onnx.checker.check_model(model)
    output.parent.mkdir(parents=True,exist_ok=True);onnx.save(model,output)
    print(f'Converted original weights: {output} ({output.stat().st_size} bytes)')

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--source',type=Path);p.add_argument('--output',type=Path,default=Path('assets/translation_models/legacy-balloon/model.onnx'));a=p.parse_args()
    if a.source:convert(a.source,a.output)
    else:
        with tempfile.TemporaryDirectory() as temp:
            folder=Path(temp);archive=folder/'legacy.zip'
            subprocess.run(['curl','--fail','--location','--retry','3','--connect-timeout','30','--max-time','600','--output',str(archive),URL],check=True)
            with zipfile.ZipFile(archive) as z:
                for name in HASHES: (folder/name).write_bytes(z.read(name))
            convert(folder,a.output)
