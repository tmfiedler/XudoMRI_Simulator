function sampled=sampleCstGrid(data,nodeAxes,targetAxes,isCellData,outsideValue)
%SAMPLECSTGRID Sample a traced CST submesh at physical target coordinates.
% Materials occupy cells bounded by nodeAxes. Fields are node-associated
% ResultReader postprocessing values. Interior cell boundaries belong to the
% right cell; the final boundary belongs to the last cell. Nearest-node
% midpoint ties choose the larger index. Outside the source domain is fill.
indices=cell(1,3);valid=cell(1,3);
for axis=1:3
 nodes=double(nodeAxes{axis}(:).');query=double(targetAxes{axis}(:).');
 if isCellData
  index=discretize(query,nodes);
 else
  edges=[-Inf,nodes(1:end-1)/2+nodes(2:end)/2,Inf];
  index=discretize(query,edges);
 end
 valid{axis}=query>=nodes(1)&query<=nodes(end)&~isnan(index);
 index(~valid{axis})=1;indices{axis}=index;
end
sampled=data(indices{:});
sampled(~valid{1},:,:)=outsideValue;sampled(:,~valid{2},:)=outsideValue;sampled(:,:,~valid{3})=outsideValue;
end
